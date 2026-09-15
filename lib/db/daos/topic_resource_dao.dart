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
  }) {
    return into(topicResources).insert(
      TopicResourcesCompanion.insert(
        subjectId: subjectId,
        topicKey: topicKey,
        termMarker: Value(termMarker),
        resourceTitle: resourceTitle,
        contentChunk: contentChunk,
        createdAt: (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
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

  /// Rows whose chunk or title contains [needle], scoped to one subject.
  ///
  /// Raw SQL rather than drift's `like()`, because this needs an `ESCAPE`
  /// clause and `like()` emits none. A teacher writing "100% yield" or
  /// "acid_base" would otherwise have their `%` and `_` read as LIKE
  /// wildcards — the first matches nearly every row, the second matches the
  /// wrong ones, and neither fails loudly enough to be noticed.
  Future<List<TopicResource>> searchChunks({
    required String subjectId,
    required String needle,
    int? termMarker,
    int limit = 60,
  }) async {
    final escaped = needle
        .toLowerCase()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final pattern = '%$escaped%';

    final termClause =
        termMarker == null ? '' : 'AND (term_marker = ? OR term_marker = ?) ';

    final rows = await customSelect(
      'SELECT * FROM topic_resources '
      'WHERE subject_id = ? '
      "  AND (lower(content_chunk) LIKE ? ESCAPE '\\' "
      "       OR lower(resource_title) LIKE ? ESCAPE '\\') "
      '$termClause'
      'LIMIT ?',
      variables: [
        Variable.withString(subjectId),
        Variable.withString(pattern),
        Variable.withString(pattern),
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
