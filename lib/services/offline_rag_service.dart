import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/otic_database.dart';
import 'offline_storage_service.dart';

/// Zero-lag full-text retrieval over teacher-supplied topic resources.
///
/// ## Why full-text search and not embeddings
///
/// The target device is a 4 GB Android phone already holding a 1.5B brain
/// and a 0.8B translator in memory. A third model for embeddings would not fit,
/// and even if it did, embedding the query on every turn would add a model load
/// to the critical path — the exact latency failure this product keeps hitting.
/// SQLite's FTS5 index (stemmed, BM25-ranked) answers in well under a
/// millisecond, needs no model at all, and stays correct with the device in
/// flight mode. It does not understand synonyms; the tutor compensates by
/// searching with the matched syllabus lesson's own vocabulary rather than
/// only the student's words (see `TutorPipeline`).
///
/// ## Relationship to the hardcoded syllabi
///
/// This service only ever reads the `topic_resources` table. It cannot reach
/// `assets/curriculum/*.json`. When a subject has no teacher resources,
/// [retrieveContextForQuery] returns an empty string and the caller falls back
/// to the core syllabus — that is the designed, common path, not an error.
class OfflineRagService {
  OfflineRagService(this._storage);

  final OfflineStorageService _storage;

  /// How many chunks reach the prompt. Three is the agreed budget: on a small
  /// model a longer fact book crowds out the student's actual question.
  static const topChunks = 3;

  /// Returns a unified context block for [userQuery], or `''` when this
  /// subject/topic has no teacher-supplied resources.
  ///
  /// Lookup order:
  ///   1. chunks filed under this exact subject **and** topic (the spec's
  ///      `subject_id = ? AND topic_key = ?` filter);
  ///   2. failing that, chunks anywhere in the same subject — a teacher who
  ///      filed "Term 2 Chemistry Notes" against one topic should still be
  ///      able to answer a question asked from a neighbouring one;
  ///   3. failing that, `''`.
  ///
  /// [subjectId] and [activeTopicKey] are normalized identically to the write
  /// path, so a caller may pass a raw lesson title ("Lesson 3: Acid–Base
  /// Balances") and still match what a teacher filed as "acid-base balances".
  Future<String> retrieveContextForQuery(
    String userQuery,
    String subjectId,
    String activeTopicKey, {
    int? termMarker,
    int limit = topChunks,
  }) async {
    final subject = normalizeSubjectId(subjectId);
    if (subject.isEmpty) return '';

    try {
      final onTopic = await _storage.chunksForTopic(
        subjectId: subject,
        topicKey: activeTopicKey,
        termMarker: termMarker,
      );

      // Material filed against this exact topic is already known to be
      // relevant, so a question carrying no usable keywords ("why?", "go on")
      // may still fall back to insertion order — the teacher's opening
      // paragraphs on the very topic the student is sitting on.
      if (onTopic.isNotEmpty) {
        final ranked =
            rankChunks(userQuery, onTopic, limit: limit, allowUnscored: true);
        if (ranked.isNotEmpty) return formatContextBlock(ranked);
      }

      // Subject-wide material is a different matter: it was filed against some
      // *other* topic. Only a real keyword hit justifies injecting it, because
      // the frame presents whatever is returned as verified fact from the
      // teacher's notes. Handing a student three arbitrary paragraphs about
      // titration when they asked "why?" about bonding would be a confident,
      // attributed non-answer — worse than no notes at all.
      final terms = keywordsOf(userQuery);
      if (terms.isEmpty) return '';
      final subjectWide = await _storage.searchChunks(
        subjectId: subject,
        needle: terms.join(' '),
        termMarker: termMarker,
      );
      return formatContextBlock(subjectWide.take(limit).toList());
    } catch (e) {
      // Retrieval is an enhancement. A failure here must degrade to "answer
      // from the core syllabus", never to a failed turn.
      debugPrint('retrieveContextForQuery failed: $e');
      return '';
    }
  }

  /// Teacher material relevant to [searchText] from any subject, as one
  /// context block, or `''` when nothing matches.
  ///
  /// The tutor chat's entry point: a free-form question carries no subject,
  /// so the full-text index is searched across all of them. Stopwords are
  /// removed first — BM25 would down-weight them anyway, but "what" and "does"
  /// still widen the candidate set for nothing.
  Future<String> retrieveAcrossSubjects(
    String searchText, {
    int limit = topChunks,
  }) async {
    final terms = keywordsOf(searchText);
    if (terms.isEmpty) return '';
    try {
      final hits = await _storage.searchAllChunks(
        needle: terms.join(' '),
        limit: limit,
      );
      return formatContextBlock(hits);
    } catch (e) {
      debugPrint('retrieveAcrossSubjects failed: $e');
      return '';
    }
  }

  /// True when this subject/topic has anything to retrieve — for a UI that
  /// wants to show that a teacher's material is in play.
  Future<bool> hasResourcesFor(String subjectId, String topicKey) async {
    final scoped = await _storage.chunksForTopic(
      subjectId: subjectId,
      topicKey: topicKey,
    );
    if (scoped.isNotEmpty) return true;
    final subjectWide = await _storage.chunksForSubject(subjectId: subjectId);
    return subjectWide.isNotEmpty;
  }
}

// ── Ranking ──────────────────────────────────────────────────────────────

/// Scores [candidates] against [query] and returns the best [limit] chunks.
///
/// Scoring is deliberately simple and explainable:
///   * +3 for each distinct query term found in the chunk body
///   * +2 for each distinct query term found in the resource title
///   * +1 when a term matches as a whole word rather than a substring
///
/// Chunks scoring zero are dropped rather than padded in — returning three
/// irrelevant paragraphs is worse than returning one relevant one, because the
/// prompt tells the model to treat the block as verified fact.
///
/// [allowUnscored] decides what happens when the query carries no usable terms
/// at all (a bare "why?", a greeting). With it set, the first [limit] chunks in
/// insertion order are returned — correct only when the caller already knows
/// every candidate is on the student's current topic. Without it, a
/// keyword-less query returns nothing, which is what subject-wide candidates
/// require: they were filed against some other topic, and relevance has to be
/// earned rather than assumed.
List<TopicResource> rankChunks(
  String query,
  List<TopicResource> candidates, {
  int limit = OfflineRagService.topChunks,
  bool allowUnscored = true,
}) {
  if (candidates.isEmpty) return const [];
  final terms = keywordsOf(query);
  if (terms.isEmpty) {
    return allowUnscored ? candidates.take(limit).toList() : const [];
  }

  final scored = <_ScoredChunk>[];
  for (final row in candidates) {
    final body = row.contentChunk.toLowerCase();
    final title = row.resourceTitle.toLowerCase();
    var score = 0;
    for (final term in terms) {
      final inBody = body.contains(term);
      if (inBody) score += 3;
      if (title.contains(term)) score += 2;
      if (inBody && RegExp('\\b${RegExp.escape(term)}\\b').hasMatch(body)) {
        score += 1;
      }
    }
    if (score > 0) scored.add(_ScoredChunk(row, score));
  }

  if (scored.isEmpty) return const [];
  // Stable: equal scores keep insertion order, so a resource reads in the
  // order the teacher wrote it rather than shuffling between turns.
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(limit).map((s) => s.row).toList();
}

/// Query terms worth matching on: lowercased, de-punctuated, stopwords and
/// one-character fragments removed.
///
/// Stopwords matter more than usual here. "What is the process of
/// neutralisation?" would otherwise match every chunk containing "the", which
/// is all of them, and the ranking would collapse to insertion order.
Set<String> keywordsOf(String query) {
  final words = query
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2 && !_stopwords.contains(w));
  return words.toSet();
}

const _stopwords = {
  'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'her',
  'was', 'one', 'our', 'out', 'has', 'him', 'his', 'how', 'its', 'may',
  'new', 'now', 'old', 'see', 'two', 'who', 'did', 'get', 'why', 'what',
  'when', 'where', 'which', 'this', 'that', 'with', 'from', 'have', 'been',
  'does', 'about', 'into', 'more', 'some', 'such', 'than', 'then', 'them',
  'these', 'they', 'will', 'would', 'could', 'should', 'there', 'their',
  'please', 'explain', 'tell', 'give', 'help', 'need', 'want', 'know',
};

/// Joins ranked chunks into one clean context block.
///
/// Duplicate chunk text is collapsed — the same paragraph appearing twice
/// pushes a small model toward repeating it — and each source is labelled with
/// its resource title so the model can attribute a fact to a document. The
/// label uses the teacher's own title and never leaks the chunk index.
String formatContextBlock(List<TopicResource> chunks) {
  if (chunks.isEmpty) return '';
  final seen = <String>{};
  final parts = <String>[];
  for (final row in chunks) {
    final body = row.contentChunk.trim();
    if (body.isEmpty || !seen.add(body)) continue;
    parts.add('${row.resourceTitle}:\n$body');
  }
  return parts.join('\n\n');
}

class _ScoredChunk {
  const _ScoredChunk(this.row, this.score);
  final TopicResource row;
  final int score;
}

// ── Providers ────────────────────────────────────────────────────────────

final offlineRagServiceProvider = Provider<OfflineRagService>((ref) {
  return OfflineRagService(ref.watch(offlineStorageServiceProvider));
});
