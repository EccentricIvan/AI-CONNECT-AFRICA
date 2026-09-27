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
    String? visibleClassUuid,
  }) {
    final q = select(topicResources)
      ..where(
        (t) => t.subjectId.equals(subjectId) & t.topicKey.equals(topicKey),
      )
      ..where((t) => _visibleTo(t, visibleClassUuid));
    if (termMarker != null) {
      // Rows marked "all terms" stay visible when a specific term is selected;
      // a textbook definition does not stop being true in Term 2.
      q.where(
        (t) =>
            t.termMarker.equals(termMarker) |
            t.termMarker.equals(kAllTermsMarker),
      );
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
    String? visibleClassUuid,
  }) {
    final q = select(topicResources)
      ..where((t) => t.subjectId.equals(subjectId))
      ..where((t) => _visibleTo(t, visibleClassUuid));
    if (termMarker != null) {
      q.where(
        (t) =>
            t.termMarker.equals(termMarker) |
            t.termMarker.equals(kAllTermsMarker),
      );
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
    String? visibleClassUuid,
  }) {
    return _search(
      needle,
      subjectId: subjectId,
      termMarker: termMarker,
      limit: limit,
      visibleClassUuid: visibleClassUuid,
    );
  }

  /// Best-matching rows for [needle] across every subject.
  ///
  /// For the tutor chat, which does not know which teacher subject a question
  /// belongs to — the index decides.
  Future<List<TopicResource>> searchAllChunks({
    required String needle,
    int limit = 20,
    String? visibleClassUuid,
  }) {
    return _search(needle, limit: limit, visibleClassUuid: visibleClassUuid);
  }

  /// Notes a learner may be tutored from: this device's own notes, plus
  /// notes received for [visibleClassUuid] — never another class's, even on
  /// a device shared between classes.
  Expression<bool> _visibleTo(
    $TopicResourcesTable t,
    String? visibleClassUuid,
  ) => visibleClassUuid == null
      ? t.classGroupUuid.isNull()
      : t.classGroupUuid.isNull() | t.classGroupUuid.equals(visibleClassUuid);

  Future<List<TopicResource>> _search(
    String needle, {
    String? subjectId,
    int? termMarker,
    required int limit,
    String? visibleClassUuid,
  }) async {
    final match = buildFtsMatch(needle);
    if (match.isEmpty) return const [];

    final rows = await customSelect(
      'SELECT t.* FROM topic_resources_fts f '
      'JOIN topic_resources t ON t.id = f.rowid '
      'WHERE topic_resources_fts MATCH ? '
      '${subjectId == null ? '' : 'AND t.subject_id = ? '}'
      '${termMarker == null ? '' : 'AND (t.term_marker = ? OR t.term_marker = ?) '}'
      'AND (t.class_group_uuid IS NULL'
      '${visibleClassUuid == null ? '' : ' OR t.class_group_uuid = ?'}) '
      // bm25() is lower-is-better, so ascending puts the best match first.
      'ORDER BY bm25(topic_resources_fts) '
      'LIMIT ?',
      variables: [
        Variable.withString(match),
        if (subjectId != null) Variable.withString(subjectId),
        if (termMarker != null) Variable.withInt(termMarker),
        if (termMarker != null) Variable.withInt(kAllTermsMarker),
        if (visibleClassUuid != null) Variable.withString(visibleClassUuid),
        Variable.withInt(limit),
      ],
      readsFrom: {topicResources},
    ).get();

    return rows.map((r) => topicResources.map(r.data)).toList();
  }

  /// Removes an entire note — every section and chunk of the document the
  /// teacher sees as [title] (or, for older rows, every chunk titled so).
  ///
  /// Scoped by subject when [subjectId] is given so two subjects can both hold
  /// a document called "Term 1 Notes" without one deletion taking out both.
  /// Returns the number of chunks removed.
  Future<int> deleteByTitle(String title, {String? subjectId}) async {
    // Its class shares go with it, or a later note with the same title
    // would silently inherit them.
    await customStatement(
      'DELETE FROM resource_shares WHERE document_title = ?'
      '${subjectId == null ? '' : ' AND subject_id = ?'}',
      [title, if (subjectId != null) subjectId],
    );
    final q = delete(topicResources)
      ..where(
        (t) => t.documentTitle.equals(title) | t.resourceTitle.equals(title),
      );
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
  Future<int> deleteBySubject(String subjectId) async {
    await customStatement('DELETE FROM resource_shares WHERE subject_id = ?', [
      subjectId,
    ]);
    return (delete(
      topicResources,
    )..where((t) => t.subjectId.equals(subjectId))).go();
  }

  // What class sync may serve lives in ClassSyncDao.sharedChunks — only
  // notes written on this device with an explicit share for the class.

  /// One row per uploaded file or typed note, for the teacher's list.
  ///
  /// Grouped in SQL by document: a file is split into sections (one per
  /// heading, for retrieval) and each section into chunks, but a teacher
  /// thinks in the files they added and must never be shown either split.
  Future<List<ResourceSummary>> listResources({String? subjectId}) async {
    final where = subjectId == null ? '' : 'WHERE subject_id = ?';
    final rows = await customSelect(
      'SELECT COALESCE(document_title, resource_title) AS resource_title, '
      '       subject_id, MIN(topic_key) AS topic_key, MIN(term_marker) AS term_marker, '
      '       COUNT(*) AS chunk_count, MIN(created_at) AS created_at '
      'FROM topic_resources $where '
      'GROUP BY COALESCE(document_title, resource_title), subject_id '
      'ORDER BY created_at DESC',
      variables: [if (subjectId != null) Variable.withString(subjectId)],
      readsFrom: {topicResources},
    ).get();

    return rows
        .map(
          (r) => ResourceSummary(
            resourceTitle: r.read<String>('resource_title'),
            subjectId: r.read<String>('subject_id'),
            topicKey: r.read<String>('topic_key'),
            termMarker: r.read<int>('term_marker'),
            chunkCount: r.read<int>('chunk_count'),
            createdAt: DateTime.tryParse(r.read<String>('created_at')),
          ),
        )
        .toList();
  }

  Future<int> countChunks() async {
    final count = topicResources.id.count();
    final row = await (selectOnly(
      topicResources,
    )..addColumns([count])).getSingle();
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
