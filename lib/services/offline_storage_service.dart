import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/daos/topic_resource_dao.dart';
import '../db/otic_database.dart';
import '../db/providers/db_provider.dart';
import '../db/tables/topic_resources_table.dart';

/// Local store for teacher-supplied notes, textbook extracts and term
/// handouts — the dynamic half of the curriculum.
///
/// ## Relationship to the hardcoded syllabi
///
/// The syllabi in `assets/curriculum/*.json`, loaded by `CurriculumService`,
/// are the permanent structural base for every subject and are **never** read,
/// written or shadowed by this service. What lives here is strictly additive:
/// extra material a teacher chose to attach to a topic the syllabus already
/// defines. With this table empty the app behaves exactly as it did before it
/// existed.
///
/// ## Why drift and not sqflite
///
/// The agreed schema is implemented verbatim — same table name, same seven
/// columns, same types — on drift rather than `sqflite`, because `sqflite` has
/// no Windows or Linux implementation without `sqflite_common_ffi`, and both
/// are shipping targets (Windows is the primary development target). Adding it
/// would also mean a second SQLite connection and a second migration timeline
/// running alongside drift's inside one app. The isolation the spec asks for
/// comes from [TopicResources] being a *new table* that nothing else joins
/// against — not from a second database engine.
class OfflineStorageService {
  OfflineStorageService(this._db);

  final OticDatabase _db;

  TopicResourceDao get _dao => _db.topicResourceDao;

  // ── Write ──────────────────────────────────────────────────────────────

  /// Stores one resource, splitting [content] into ~500-character chunks.
  ///
  /// This is the method a teacher-facing "Add Lesson Note" action calls. It
  /// takes the whole document and does the splitting itself: chunk size is an
  /// internal retrieval detail and must never reach the teacher as a decision
  /// they are asked to make.
  ///
  /// [subjectId] and [topicKey] are normalized on the way in, and
  /// [OfflineRagService] normalizes identically on the way out, so the two
  /// sides cannot drift apart. Returns the number of chunks written.
  Future<int> insertTopicResource({
    required String subjectId,
    required String topicKey,
    required String resourceTitle,
    required String content,
    int termMarker = kAllTermsMarker,
    DateTime? createdAt,
  }) async {
    final title = resourceTitle.trim();
    final body = content.trim();
    if (title.isEmpty || body.isEmpty) return 0;

    final subject = normalizeSubjectId(subjectId);
    final topic = normalizeTopicKey(topicKey);
    if (subject.isEmpty || topic.isEmpty) return 0;

    final term =
        kTermMarkers.contains(termMarker) ? termMarker : kAllTermsMarker;
    final stamp = (createdAt ?? DateTime.now()).toUtc().toIso8601String();
    final chunks = chunkContent(body);

    try {
      await _dao.insertChunks([
        for (final chunk in chunks)
          TopicResourcesCompanion.insert(
            subjectId: subject,
            topicKey: topic,
            termMarker: Value(term),
            resourceTitle: title,
            contentChunk: chunk,
            createdAt: stamp,
          ),
      ]);
      return chunks.length;
    } catch (e) {
      debugPrint('insertTopicResource failed for "$title": $e');
      return 0;
    }
  }

  /// Stores a single pre-chunked row. For importers that have already split a
  /// document; ordinary callers want [insertTopicResource].
  Future<int> insertTopicResourceChunk({
    required String subjectId,
    required String topicKey,
    required String resourceTitle,
    required String contentChunk,
    int termMarker = kAllTermsMarker,
    DateTime? createdAt,
  }) async {
    try {
      return await _dao.insertChunk(
        subjectId: normalizeSubjectId(subjectId),
        topicKey: normalizeTopicKey(topicKey),
        termMarker:
            kTermMarkers.contains(termMarker) ? termMarker : kAllTermsMarker,
        resourceTitle: resourceTitle.trim(),
        contentChunk: contentChunk,
        createdAt: createdAt,
      );
    } catch (e) {
      debugPrint('insertTopicResourceChunk failed: $e');
      return 0;
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  /// Removes a resource completely — every chunk that shares [resourceTitle].
  ///
  /// Returns the number of chunks removed; 0 means nothing matched, which a
  /// caller should report as "nothing to remove" rather than as a failure.
  Future<int> deleteTopicResourceByTitle(
    String resourceTitle, {
    String? subjectId,
  }) async {
    final title = resourceTitle.trim();
    if (title.isEmpty) return 0;
    try {
      return await _dao.deleteByTitle(
        title,
        subjectId: subjectId == null ? null : normalizeSubjectId(subjectId),
      );
    } catch (e) {
      debugPrint('deleteTopicResourceByTitle failed for "$title": $e');
      return 0;
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────

  /// Every resource a teacher has added, newest first, chunking collapsed.
  Future<List<ResourceSummary>> listResources({String? subjectId}) async {
    try {
      return await _dao.listResources(
        subjectId: subjectId == null ? null : normalizeSubjectId(subjectId),
      );
    } catch (e) {
      debugPrint('listResources failed: $e');
      return const [];
    }
  }

  /// Candidate chunks for one topic. Used by [OfflineRagService]; ranking and
  /// selection happen there, not here.
  Future<List<TopicResource>> chunksForTopic({
    required String subjectId,
    required String topicKey,
    int? termMarker,
  }) async {
    try {
      return await _dao.chunksForTopic(
        subjectId: normalizeSubjectId(subjectId),
        topicKey: normalizeTopicKey(topicKey),
        termMarker: termMarker,
      );
    } catch (e) {
      debugPrint('chunksForTopic failed: $e');
      return const [];
    }
  }

  Future<List<TopicResource>> chunksForSubject({
    required String subjectId,
    int? termMarker,
  }) async {
    try {
      return await _dao.chunksForSubject(
        subjectId: normalizeSubjectId(subjectId),
        termMarker: termMarker,
      );
    } catch (e) {
      debugPrint('chunksForSubject failed: $e');
      return const [];
    }
  }

  /// `LIKE`-filtered chunks for one subject.
  Future<List<TopicResource>> searchChunks({
    required String subjectId,
    required String needle,
    int? termMarker,
  }) async {
    final trimmed = needle.trim();
    if (trimmed.isEmpty) return const [];
    try {
      return await _dao.searchChunks(
        subjectId: normalizeSubjectId(subjectId),
        needle: trimmed,
        termMarker: termMarker,
      );
    } catch (e) {
      debugPrint('searchChunks failed: $e');
      return const [];
    }
  }

  /// True when at least one teacher resource exists at all.
  Future<bool> hasAnyResources() async {
    try {
      return await _dao.countChunks() > 0;
    } catch (_) {
      return false;
    }
  }
}

// ── Key normalization ────────────────────────────────────────────────────
//
// The single most important thing in this file. Retrieval filters on exact
// equality of `subject_id` and `topic_key`; if the teacher-facing write path
// and the chat read path spell either differently, every query matches zero
// rows, nothing throws, every test that uses one spelling passes, and the
// feature is silently dead. Both paths go through these two functions.

/// Canonical form of a curriculum subject id.
///
/// The hardcoded subjects are bare lowercase ids (`chemistry`, `mathematics`,
/// `web_development`). A level suffix such as `chemistry_s4` is preserved
/// as-is — it just has to be spelled the same way on both sides.
String normalizeSubjectId(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+'), '')
      .replaceAll(RegExp(r'_+$'), '');
}

/// Canonical form of a topic key, derived from a syllabus lesson title.
///
/// `Lesson` carries a `title`, not a key, so the title *is* the identity of a
/// topic. Normalizing folds away the differences that would otherwise split
/// one topic into several: case, an en dash versus a hyphen, a "Lesson 3:"
/// prefix, punctuation and repeated spaces.
///
/// "Lesson 3: Acid–Base Balances" and "acid-base balances" both become
/// `acid_base_balances`.
String normalizeTopicKey(String raw) {
  var t = raw.trim().toLowerCase();
  t = t.replaceAll(
    RegExp(r'^(lesson|unit|topic|chapter)\s*\d*\s*[:.\-]\s*'),
    '',
  );
  t = t.replaceAll(RegExp(r'[‐-―]'), '-'); // en/em dashes → hyphen
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  t = t.replaceAll(RegExp(r'^_+'), '').replaceAll(RegExp(r'_+$'), '');
  return t;
}

/// Splits [content] into chunks of about [size] characters, breaking on a
/// paragraph or sentence boundary rather than mid-word.
///
/// A chunk that starts mid-sentence reads as broken text to the model as much
/// as to a person, and a retrieval that returns three of them wastes the
/// prompt budget it was given. Overlap is deliberately omitted: it multiplies
/// row count for material that is already small, and duplicate sentences in a
/// prompt push a 0.6B model toward repeating them.
List<String> chunkContent(String content, {int size = kResourceChunkSize}) {
  final text = content.trim().replaceAll(RegExp(r'\r\n?'), '\n');
  if (text.isEmpty) return const [];
  if (text.length <= size) return [text];

  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    final end = start + size;
    if (end >= text.length) {
      final tail = text.substring(start).trim();
      if (tail.isNotEmpty) chunks.add(tail);
      break;
    }
    // Prefer a paragraph break, then a sentence end, then a space — but only
    // when one exists in the back half of the window, so a run of unbroken
    // text cannot collapse the chunk to a few characters.
    final floor = start + (size * 0.5).round();
    var cut = text.lastIndexOf('\n\n', end);
    if (cut < floor) {
      final sentence = RegExp(r'[.!?]\s').allMatches(text.substring(start, end));
      cut = sentence.isEmpty ? -1 : start + sentence.last.start;
    }
    if (cut >= floor) {
      cut += 1;
    } else {
      cut = text.lastIndexOf(' ', end);
      if (cut < floor) cut = end; // no boundary at all: hard cut
    }
    final piece = text.substring(start, cut).trim();
    if (piece.isNotEmpty) chunks.add(piece);
    start = cut;
  }
  return chunks;
}

// ── Providers ────────────────────────────────────────────────────────────

final offlineStorageServiceProvider = Provider<OfflineStorageService>((ref) {
  return OfflineStorageService(ref.watch(dbProvider));
});

/// Teacher-visible resource list for a subject (null = every subject).
final topicResourcesProvider =
    FutureProvider.family<List<ResourceSummary>, String?>((ref, subjectId) {
  return ref.watch(offlineStorageServiceProvider).listResources(
        subjectId: subjectId,
      );
});
