import 'package:drift/drift.dart';

import '../../collaboration/sync/class_crypto.dart';
import '../../collaboration/sync/sync_ids.dart';
import '../otic_database.dart';
import '../tables/class_groups_table.dart';
import '../tables/resource_shares_table.dart';
import '../tables/sync_identity_table.dart';
import '../tables/sync_state_table.dart';
import '../tables/topic_resources_table.dart';

part 'class_sync_dao.g.dart';

/// Everything class sync decides "who gets what" from.
///
/// The serving rule lives in one query, [sharedChunks]: a chunk goes to a
/// class only if it was written on this device (not received from another
/// teacher) *and* its note has an explicit share row for that class. Notes
/// nobody shared, and notes this device received, are never served.
@DriftAccessor(
  tables: [
    ClassGroups,
    ResourceShares,
    SyncIdentity,
    TopicResources,
    SyncState,
  ],
)
class ClassSyncDao extends DatabaseAccessor<OticDatabase>
    with _$ClassSyncDaoMixin {
  ClassSyncDao(super.db);

  // ── This device ─────────────────────────────────────────────────────────

  /// This device's identity, creating its signing key the first time.
  Future<SyncIdentityData> identity() async {
    final row = await (select(
      syncIdentity,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    if (row != null) return row;
    await into(syncIdentity).insert(
      SyncIdentityCompanion.insert(
        id: const Value(1),
        signingSeed: newSigningSeed(),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(syncIdentity)..where((t) => t.id.equals(1))).getSingle();
  }

  Stream<SyncIdentityData?> watchIdentity() =>
      (select(syncIdentity)..where((t) => t.id.equals(1))).watchSingleOrNull();

  /// Names this device's school (Admin). Renaming keeps the school's id, so
  /// classes already joined stay valid.
  Future<void> setSchoolName(String name) async {
    final me = await identity();
    await (update(syncIdentity)..where((t) => t.id.equals(1))).write(
      SyncIdentityCompanion(
        schoolId: Value(me.schoolId ?? newSyncId()),
        schoolName: Value(name.trim()),
      ),
    );
  }

  /// A student device takes its school from the first class it joins.
  Future<void> adoptSchool({
    required String schoolId,
    required String schoolName,
  }) async {
    final me = await identity();
    if (me.schoolId != null) return;
    await (update(syncIdentity)..where((t) => t.id.equals(1))).write(
      SyncIdentityCompanion(
        schoolId: Value(schoolId),
        schoolName: Value(schoolName),
      ),
    );
  }

  // ── Classes ─────────────────────────────────────────────────────────────

  /// Classes this device created — the only ones it may ever serve or
  /// share notes with.
  Future<List<ClassGroup>> ownedClasses() =>
      (select(classGroups)
            ..where((t) => t.joined.equals(false) & t.groupUuid.isNotNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.className),
              (t) => OrderingTerm.asc(t.streamName),
            ]))
          .get();

  Stream<List<ClassGroup>> watchOwnedClasses() =>
      (select(classGroups)
            ..where((t) => t.joined.equals(false) & t.groupUuid.isNotNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.className),
              (t) => OrderingTerm.asc(t.streamName),
            ]))
          .watch();

  Future<ClassGroup?> ownedByUuid(String uuid) =>
      (select(classGroups)
            ..where((t) => t.groupUuid.equals(uuid) & t.joined.equals(false)))
          .getSingleOrNull();

  /// Gives an owned class its key and school the first time it's synced.
  Future<ClassGroup> ensureClassKey(ClassGroup group) async {
    if (group.classKey != null && group.schoolId != null) return group;
    final me = await identity();
    await (update(classGroups)..where((t) => t.id.equals(group.id))).write(
      ClassGroupsCompanion(
        classKey: Value(group.classKey ?? newClassKey()),
        schoolId: Value(group.schoolId ?? me.schoolId),
      ),
    );
    return (select(
      classGroups,
    )..where((t) => t.id.equals(group.id))).getSingle();
  }

  /// Records a class joined from a teacher (student device). Returns null
  /// when this device itself owns a class with that id — it is the teacher.
  Future<ClassGroup?> upsertJoinedClass({
    required String groupUuid,
    required String className,
    String? streamName,
    required String schoolId,
    required String classKey,
    required String teacherPublicKey,
  }) async {
    final existing = await (select(
      classGroups,
    )..where((t) => t.groupUuid.equals(groupUuid))).getSingleOrNull();
    final values = ClassGroupsCompanion(
      className: Value(className),
      streamName: Value(streamName),
      schoolId: Value(schoolId),
      classKey: Value(classKey),
      teacherPublicKey: Value(teacherPublicKey),
      joined: const Value(true),
    );
    if (existing != null) {
      if (!existing.joined) return null;
      await (update(
        classGroups,
      )..where((t) => t.id.equals(existing.id))).write(values);
    } else {
      await into(
        classGroups,
      ).insert(values.copyWith(groupUuid: Value(groupUuid)));
    }
    return (select(
      classGroups,
    )..where((t) => t.groupUuid.equals(groupUuid))).getSingle();
  }

  // ── Shares (teacher device) ─────────────────────────────────────────────

  /// Classes each note of [subjectId] is shared with, keyed by the note's
  /// document title (what the teacher's list shows).
  Stream<Map<String, Set<String>>> watchSharesForSubject(String subjectId) =>
      (select(
        resourceShares,
      )..where((t) => t.subjectId.equals(subjectId))).watch().map((rows) {
        final out = <String, Set<String>>{};
        for (final r in rows) {
          (out[r.documentTitle] ??= {}).add(r.classGroupUuid);
        }
        return out;
      });

  /// Shares one note — a whole uploaded file, every section of it — with
  /// exactly [classUuids]. Only classes this device owns are kept, whatever
  /// the caller passes.
  Future<void> setShares({
    required String subjectId,
    required String documentTitle,
    required Set<String> classUuids,
  }) async {
    final owned = {for (final c in await ownedClasses()) c.groupUuid!};
    await transaction(() async {
      await (delete(resourceShares)..where(
            (t) =>
                t.subjectId.equals(subjectId) &
                t.documentTitle.equals(documentTitle),
          ))
          .go();
      for (final uuid in classUuids.intersection(owned)) {
        await into(resourceShares).insert(
          ResourceSharesCompanion.insert(
            subjectId: subjectId,
            documentTitle: documentTitle,
            classGroupUuid: uuid,
          ),
        );
      }
    });
  }

  // ── Serving (teacher device) ────────────────────────────────────────────

  static const _servedJoin =
      'FROM topic_resources t '
      'JOIN resource_shares s '
      '  ON s.subject_id = t.subject_id '
      '  AND s.document_title = COALESCE(t.document_title, t.resource_title) '
      'WHERE s.class_group_uuid = ? '
      // Written here, not received from another device: received notes are
      // never passed on.
      '  AND t.class_group_uuid IS NULL';

  /// Subjects [classUuid] has at least one shared note in.
  Future<List<String>> sharedSubjects(String classUuid) async {
    final rows = await customSelect(
      'SELECT DISTINCT t.subject_id AS subject_id $_servedJoin ORDER BY t.subject_id',
      variables: [Variable.withString(classUuid)],
      readsFrom: {topicResources, resourceShares},
    ).get();
    return [for (final r in rows) r.read<String>('subject_id')];
  }

  /// Every chunk [classUuid] may receive in [subjectId].
  Future<List<TopicResource>> sharedChunks(
    String classUuid,
    String subjectId,
  ) async {
    final rows = await customSelect(
      'SELECT t.* $_servedJoin AND t.subject_id = ? ORDER BY t.id',
      variables: [
        Variable.withString(classUuid),
        Variable.withString(subjectId),
      ],
      readsFrom: {topicResources, resourceShares},
    ).get();
    return [for (final r in rows) topicResources.map(r.data)];
  }

  // ── Receiving (student device) ──────────────────────────────────────────

  Future<String?> channelDigestFor(String classUuid, String subjectId) async {
    final row =
        await (select(syncState)..where(
              (t) =>
                  t.classGroupUuid.equals(classUuid) &
                  t.subjectId.equals(subjectId),
            ))
            .getSingleOrNull();
    return row?.channelDigest;
  }

  /// Replaces this device's copy of one class+subject channel in one
  /// transaction — edits and removals on the teacher's side arrive as-is,
  /// with no duplicates left behind.
  Future<void> replaceChannel({
    required String classUuid,
    required String subjectId,
    required List<TopicResourcesCompanion> rows,
    required String digest,
  }) => transaction(() async {
    await (delete(topicResources)..where(
          (t) =>
              t.classGroupUuid.equals(classUuid) &
              t.subjectId.equals(subjectId),
        ))
        .go();
    for (var i = 0; i < rows.length; i += 50) {
      await batch(
        (b) => b.insertAll(
          topicResources,
          rows.sublist(i, (i + 50).clamp(0, rows.length)),
        ),
      );
    }
    final at = DateTime.now().toUtc().toIso8601String();
    await into(syncState).insert(
      SyncStateCompanion.insert(
        classGroupUuid: classUuid,
        subjectId: subjectId,
        lastSyncedAt: at,
        channelDigest: Value(digest),
      ),
      onConflict: DoUpdate(
        (_) => SyncStateCompanion(
          lastSyncedAt: Value(at),
          channelDigest: Value(digest),
        ),
        target: [syncState.classGroupUuid, syncState.subjectId],
      ),
    );
  });

  /// Drops channels of [classUuid] the teacher no longer shares.
  Future<int> dropChannelsExcept(
    String classUuid,
    Set<String> keepSubjects,
  ) => transaction(() async {
    final gone =
        (await (select(
              syncState,
            )..where((t) => t.classGroupUuid.equals(classUuid))).get())
            .map((r) => r.subjectId)
            .toSet();
    final localSubjects = await customSelect(
      'SELECT DISTINCT subject_id FROM topic_resources WHERE class_group_uuid = ?',
      variables: [Variable.withString(classUuid)],
      readsFrom: {topicResources},
    ).get();
    gone.addAll(localSubjects.map((r) => r.read<String>('subject_id')));
    gone.removeAll(keepSubjects);
    for (final subject in gone) {
      await (delete(topicResources)..where(
            (t) =>
                t.classGroupUuid.equals(classUuid) &
                t.subjectId.equals(subject),
          ))
          .go();
      await (delete(syncState)..where(
            (t) =>
                t.classGroupUuid.equals(classUuid) &
                t.subjectId.equals(subject),
          ))
          .go();
    }
    return gone.length;
  });
}
