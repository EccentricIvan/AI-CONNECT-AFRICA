import 'package:drift/drift.dart';

import '../otic_database.dart';
import '../tables/topic_resources_table.dart';

part 'topic_resource_dao.g.dart';

/// Read/write access to teacher-supplied topic resources.
///
/// Every method here is additive to the hardcoded syllabi: nothing in this DAO
/// can read, alter or shadow `assets/curriculum/*.json`. An empty table is a
/// fully supported state — [chunksForTopic] returns `[]` and the tutor runs on
/// the core syllabus exactly as it did before this feature existed.
@DriftAccessor(tables: [TopicResources])
class TopicResourceDao extends DatabaseAccessor<OticDatabase>
    with _$TopicResourceDaoMixin {
  TopicResourceDao(super.db);

  /// Inserts one chunk. Returns the new row id.
  ///
  /// Callers should normalize [subjectId] and [topicKey] first (the
  /// `OfflineStorageService` facade does this for them) — a raw lesson title
  /// written here would never be found by a retrieval that normalizes.
  Future<int> insertChunk({
    required String subjectId,
    required String topicKey,
    required int termMarker,
    required String resourceTitle,
    required String contentChunk,
    DateTime? createdAt,
    /// Scoped sync: which class/stream this chunk is pushed to
    /// ([ClassGroups.groupUuid]). Null means every class — see the column
    /// doc on [TopicResources.classGroupUuid].
    String? classGroupUuid,
  }) {
    final at = (createdAt ?? DateTime.now()).toUtc().toIso8601String();
    return into(topicResources).insert(
      TopicResourcesCompanion.insert(
        subjectId: subjectId,
        topicKey: topicKey,
        termMarker: Value(termMarker),
        resourceTitle: resourceTitle,
        contentChunk: contentChunk,
        createdAt: at,
        classGroupUuid: Value(classGroupUuid),
        updatedAt: Value(at),
      ),
    );
  }

  /// Inserts many chunks of one document in a single transaction, so a
  /// half-written resource can never be left behind by an interrupted import.
  Future<void> insertChunks(List<TopicResourcesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(topicResources, rows));
  }

  /// Candidate rows for a retrieval: one subject, one topic, optionally one
  /// term.
  ///
  /// Ranking happens in Dart rather than SQL — the row count per topic is
  /// small (a handful of documents), and scoring here keeps the relevance
  /// rule in one readable place instead of spread across a query string.
  Future<List<TopicResource>> chunksForTopic({
    required String subjectId,
    required String topicKey,
    int? termMarker,
    int limit = 200,
  }) {
    final q = select(topicResources)
      ..where((t) => t.subjectId.equals(subjectId) & t.topicKey.equals(topicKey));
    if (termMarker != null) {
      // Rows marked "all terms" stay visible when a specific term is selected;
      // a textbook definition does not stop being true in Term 2.
      q.where((t) =>
          t.termMarker.equals(termMarker) |
          t.termMarker.equals(kAllTermsMarker));
    }
    q.limit(limit);
    return q.get();
  }

  /// Every chunk for a subject, regardless of topic — the fallback a retrieval
  /// uses when the active topic has no resources of its own.
  Future<List<TopicResource>> chunksForSubject({
    required String subjectId,
    int? termMarker,
    int limit = 400,
  }) {
    final q = select(topicResources)
      ..where((t) => t.subjectId.equals(subjectId));
    if (termMarker != null) {
      q.where((t) =>
          t.termMarker.equals(termMarker) |
          t.termMarker.equals(kAllTermsMarker));
    }
    q.limit(limit);
    return q.get();
  }

  /// Best-matching rows for [needle] within one subject, most relevant first.
  ///
  /// Full-text search over the `topic_resources_fts` index (see
  /// `OticDatabase._createResourceSearchIndex`), ranked by BM25. [needle] is
  /// free text; it is turned into a safe `MATCH` expression by
  /// [buildFtsMatch], so a teacher's or student's punctuation can never be
  /// read as FTS5 query syntax.
  Future<List<TopicResource>> searchChunks({
    required String subjectId,
    required String needle,
    int? termMarker,
    int limit = 60,
  }) {
    return _search(
      needle,
      subjectId: subjectId,
      termMarker: termMarker,
      limit: limit,
    );
  }

  /// Best-matching rows for [needle] across every subject.
  ///
  /// For the tutor chat, which does not know which teacher subject a question
  /// belongs to — the index decides.
  Future<List<TopicResource>> searchAllChunks({
    required String needle,
    int limit = 20,
  }) {
    return _search(needle, limit: limit);
  }

  Future<List<TopicResource>> _search(
    String needle, {
    String? subjectId,
    int? termMarker,
    required int limit,
  }) async {
    final match = buildFtsMatch(needle);
    if (match.isEmpty) return const [];

    final rows = await customSelect(
      'SELECT t.* FROM topic_resources_fts f '
      'JOIN topic_resources t ON t.id = f.rowid '
      'WHERE topic_resources_fts MATCH ? '
      '${subjectId == null ? '' : 'AND t.subject_id = ? '}'
      '${termMarker == null ? '' : 'AND (t.term_marker = ? OR t.term_marker = ?) '}'
      // bm25() is lower-is-better, so ascending puts the best match first.
      'ORDER BY bm25(topic_resources_fts) '
      'LIMIT ?',
      variables: [
        Variable.withString(match),
        if (subjectId != null) Variable.withString(subjectId),
        if (termMarker != null) Variable.withInt(termMarker),
        if (termMarker != null) Variable.withInt(kAllTermsMarker),
        Variable.withInt(limit),
      ],
      readsFrom: {topicResources},
    ).get();

    return rows.map((r) => topicResources.map(r.data)).toList();
  }

  /// Removes an entire resource — every chunk sharing [resourceTitle].
  ///
  /// Scoped by subject when [subjectId] is given so two subjects can both hold
  /// a document called "Term 1 Notes" without one deletion taking out both.
  /// Returns the number of chunks removed.
  Future<int> deleteByTitle(String resourceTitle, {String? subjectId}) {
    final q = delete(topicResources)
      ..where((t) => t.resourceTitle.equals(resourceTitle));
    if (subjectId != null) {
      q.where((t) => t.subjectId.equals(subjectId));
    }
    return q.go();
  }

  /// Removes every resource belonging to a subject.
  ///
  /// Used when a teacher deletes a custom subject: the subject row and its
  /// material go together, or the material becomes unreachable rows that no
  /// screen can list and no one can delete.
  Future<int> deleteBySubject(String subjectId) {
    return (delete(topicResources)..where((t) => t.subjectId.equals(subjectId)))
        .go();
  }

  // ── Scoped sync (lib/collaboration/sync/) ─────────────────────────────────

  /// Every subject with material for [classGroupUuid] (or scoped to every
  /// class), with its newest [TopicResources.updatedAt] — the handshake
  /// answer: "these are the channels you can pull, and how fresh each is".
  Future<List<SubjectVersion>> subjectVersionsForClass(
      String classGroupUuid) async {
    final rows = await customSelect(
      'SELECT subject_id, MAX(COALESCE(updated_at, created_at)) AS version '
      'FROM topic_resources '
      'WHERE class_group_uuid IS NULL OR class_group_uuid = ? '
      'GROUP BY subject_id',
      variables: [Variable.withString(classGroupUuid)],
      readsFrom: {topicResources},
    ).get();
    return rows
        .map((r) => SubjectVersion(
              subjectId: r.read<String>('subject_id'),
              version: r.read<String>('version'),
            ))
        .toList();
  }

  /// Chunks for one class+subject channel, newer than [sinceIso] — the
  /// `/sync/channel` answer. `since` compares as text: both sides always
  /// write ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SS.mmmmmmZ`), which sorts
  /// correctly as a plain string, so this needs no date parsing in SQL.
  /// `COALESCE(updated_at, created_at)` so a chunk written before this
  /// column existed (updated_at NULL) is still reachable by a sync, instead
  /// of a NULL comparison silently dropping it from every channel forever.
  Future<List<TopicResource>> channelChunks({
    required String classGroupUuid,
    required String subjectId,
    required String sinceIso,
  }) async {
    final rows = await customSelect(
      'SELECT * FROM topic_resources '
      'WHERE (class_group_uuid IS NULL OR class_group_uuid = ?) '
      '  AND subject_id = ? '
      '  AND COALESCE(updated_at, created_at) > ? '
      'ORDER BY COALESCE(updated_at, created_at) ASC',
      variables: [
        Variable.withString(classGroupUuid),
        Variable.withString(subjectId),
        Variable.withString(sinceIso),
      ],
      readsFrom: {topicResources},
    ).get();
    return rows.map((r) => topicResources.map(r.data)).toList();
  }

  /// One row per distinct resource, for the teacher's resource list.
  ///
  /// Grouped in SQL: a resource is many chunks, but a teacher thinks in
  /// documents and must never be shown the chunking.
  Future<List<ResourceSummary>> listResources({String? subjectId}) async {
    final where = subjectId == null ? '' : 'WHERE subject_id = ?';
    final rows = await customSelect(
      'SELECT resource_title, subject_id, topic_key, term_marker, '
      '       COUNT(*) AS chunk_count, MIN(created_at) AS created_at '
      'FROM topic_resources $where '
      'GROUP BY resource_title, subject_id, topic_key, term_marker '
      'ORDER BY created_at DESC',
      variables: [if (subjectId != null) Variable.withString(subjectId)],
      readsFrom: {topicResources},
    ).get();

    return rows
        .map((r) => ResourceSummary(
              resourceTitle: r.read<String>('resource_title'),
              subjectId: r.read<String>('subject_id'),
              topicKey: r.read<String>('topic_key'),
              termMarker: r.read<int>('term_marker'),
              chunkCount: r.read<int>('chunk_count'),
              createdAt: DateTime.tryParse(r.read<String>('created_at')),
            ))
        .toList();
  }

  Future<int> countChunks() async {
    final count = topicResources.id.count();
    final row =
        await (selectOnly(topicResources)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Wipes every teacher resource. The hardcoded syllabi are untouched.
  Future<void> clear() => delete(topicResources).go();
}

/// One syncable subject channel and how fresh it is — a handshake row.
class SubjectVersion {
  const SubjectVersion({required this.subjectId, required this.version});

  final String subjectId;

  /// ISO-8601 UTC — the newest chunk's `COALESCE(updated_at, created_at)`.
  final String version;
}

/// One teacher-visible resource, with its chunking already collapsed away.
class ResourceSummary {
  const ResourceSummary({
    required this.resourceTitle,
    required this.subjectId,
    required this.topicKey,
    required this.termMarker,
    required this.chunkCount,
    this.createdAt,
  });

  final String resourceTitle;
  final String subjectId;
  final String topicKey;
  final int termMarker;

  /// Internal detail — never render this in a teacher-facing view.
  final int chunkCount;

  final DateTime? createdAt;
}

/// Turns free text into an FTS5 `MATCH` expression, or `''` when nothing in
/// it is searchable.
///
/// Every term is double-quoted, which makes it a literal token: FTS5 gives
/// `-`, `:`, `*`, `^`, parentheses and the words AND/OR/NOT/NEAR special
/// meaning, and unquoted student text would either throw a syntax error or
/// silently search for something else. Terms are OR-ed — a question matches
/// on any of its words and BM25 ranks chunks that hit more of them higher.
///
/// The porter tokenizer folds inflections but not derivations
/// ("photosynthesizing" does not stem to "photosynthesis"), so long terms also
/// get a truncated prefix term, which does catch those.
String buildFtsMatch(String text) {
  final terms = text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 2)
      .toSet();
  final parts = <String>{};
  for (final term in terms) {
    parts.add('"$term"');
    if (term.length >= 8) {
      final keep = (term.length * 0.7).round().clamp(5, term.length - 1);
      parts.add('"${term.substring(0, keep)}"*');
    }
  }
  return parts.join(' OR ');
}
