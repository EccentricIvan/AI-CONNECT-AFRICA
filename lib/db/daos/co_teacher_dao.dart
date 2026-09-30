import 'dart:convert';

import 'package:drift/drift.dart';

import '../../collaboration/sync/class_crypto.dart';
import '../otic_database.dart';
import '../tables/class_groups_table.dart';
import '../tables/co_teachers_table.dart';
import '../tables/co_teaching_classes_table.dart';
import '../tables/sync_identity_table.dart';

part 'co_teacher_dao.g.dart';

/// Co-teachers: a root teacher device delegating specific subjects of a
/// class to other teacher devices, each serving from their own device with
/// their own signing key.
///
/// Root device: [ClassCoTeachers] is the source of truth for who is
/// allocated what; [rosterFor] builds and signs the [ClassRoster] form of
/// it that travels to students and co-teachers.
/// Co-teacher device: [CoTeachingClasses] is "classes I serve as a
/// delegate" — kept separate from `ClassGroups` on purpose, so a delegated
/// class is never mistaken for one this device owns or joined as a student.
@DriftAccessor(
  tables: [ClassCoTeachers, CoTeachingClasses, ClassGroups, SyncIdentity],
)
class CoTeacherDao extends DatabaseAccessor<OticDatabase>
    with _$CoTeacherDaoMixin {
  CoTeacherDao(super.db);

  // ── Root device: who is allocated what ──────────────────────────────────

  Stream<List<ClassCoTeacher>> watchCoTeachers(String classUuid) =>
      (select(classCoTeachers)
            ..where((t) => t.classGroupUuid.equals(classUuid))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<ClassCoTeacher>> coTeachersFor(String classUuid) =>
      (select(classCoTeachers)
            ..where((t) => t.classGroupUuid.equals(classUuid)))
          .get();

  /// Every subject already allocated to a co-teacher of [classUuid] — never
  /// offer these again when inviting another.
  Future<Set<String>> allocatedSubjects(String classUuid) async {
    final rows = await coTeachersFor(classUuid);
    return {
      for (final r in rows) ...(_decodeSubjects(r.subjectIdsJson)),
    };
  }

  /// Adds a co-teacher allocation and republishes the class's signed
  /// roster. False (and no change made) if any of [subjectIds] is already
  /// allocated to someone else — allocation must stay disjoint, since two
  /// signers owning the same channel would race their independent version
  /// counters (see `sync_state.signer_versions_json`).
  Future<bool> addCoTeacher({
    required ClassGroup group,
    required String publicKey,
    required String name,
    required List<String> subjectIds,
  }) async {
    final classUuid = group.groupUuid!;
    final already = await allocatedSubjects(classUuid);
    if (subjectIds.any(already.contains)) return false;
    await into(classCoTeachers).insert(
      ClassCoTeachersCompanion.insert(
        classGroupUuid: classUuid,
        publicKey: publicKey,
        name: name,
        subjectIdsJson: jsonEncode(subjectIds),
      ),
      mode: InsertMode.insertOrReplace,
    );
    await _republishRoster(group);
    return true;
  }

  /// Removes a co-teacher's allocation and republishes the roster at a new
  /// version. Hard delete — no soft-revoke flag, matching this codebase's
  /// explicit-cleanup pattern (see `LearnerDataWiper`). Revocation itself
  /// doesn't touch content: a client applies it by dropping the channel on
  /// its next sync against the newer roster (`applyRosterRevocations` in
  /// `SelectiveSyncManager`).
  Future<void> revokeCoTeacher(ClassGroup group, String publicKey) async {
    await (delete(classCoTeachers)..where(
          (t) =>
              t.classGroupUuid.equals(group.groupUuid!) &
              t.publicKey.equals(publicKey),
        ))
        .go();
    await _republishRoster(group);
  }

  Future<void> _republishRoster(ClassGroup group) async {
    final classUuid = group.groupUuid!;
    final fresh = await (select(
      classGroups,
    )..where((t) => t.id.equals(group.id))).getSingle();
    final rows = await coTeachersFor(classUuid);
    final entries = [
      for (final r in rows)
        RosterEntry(
          publicKey: r.publicKey,
          name: r.name,
          subjectIds: _decodeSubjects(r.subjectIdsJson),
        ),
    ];
    final version = (fresh.rosterVersion ?? 0) + 1;
    final me = await (select(
      syncIdentity,
    )..where((t) => t.id.equals(1))).getSingle();
    final signature = await signRoster(
      signingSeed: me.signingSeed,
      schoolId: fresh.schoolId!,
      classUuid: classUuid,
      version: version,
      entries: entries,
    );
    final roster = ClassRoster(
      schoolId: fresh.schoolId!,
      classUuid: classUuid,
      version: version,
      entries: entries,
      signature: signature,
    );
    await (update(classGroups)..where((t) => t.id.equals(group.id))).write(
      ClassGroupsCompanion(
        rosterVersion: Value(version),
        rosterJson: Value(jsonEncode(roster.toJson())),
      ),
    );
  }

  /// The class's current roster (root device only), or null if it has never
  /// had a co-teacher.
  Future<ClassRoster?> rosterFor(ClassGroup group) async {
    if (group.rosterJson == null) return null;
    return ClassRoster.fromJson(
      jsonDecode(group.rosterJson!),
      schoolId: group.schoolId!,
      classUuid: group.groupUuid!,
    );
  }

  static List<String> _decodeSubjects(String json) => [
    for (final s in jsonDecode(json) as List)
      if (s is String) s,
  ];

  // ── Co-teacher device: classes I serve as a delegate ────────────────────

  Stream<List<CoTeachingClass>> watchDelegatedClasses() =>
      (select(coTeachingClasses)
            ..orderBy([(t) => OrderingTerm.asc(t.className)]))
          .watch();

  Future<List<CoTeachingClass>> delegatedClasses() =>
      select(coTeachingClasses).get();

  Future<CoTeachingClass?> delegatedByUuid(String classUuid) =>
      (select(
        coTeachingClasses,
      )..where((t) => t.classGroupUuid.equals(classUuid))).getSingleOrNull();

  /// Stores or refreshes this device's delegation on [classUuid], as handed
  /// over by the root teacher at invite accept (or on a later re-sync).
  Future<void> upsertDelegatedClass({
    required String classUuid,
    required String className,
    String? streamName,
    required String schoolId,
    required String classKey,
    required String rootPublicKey,
    required List<String> subjectIds,
    required ClassRoster roster,
  }) async {
    await into(coTeachingClasses).insert(
      CoTeachingClassesCompanion.insert(
        classGroupUuid: classUuid,
        className: className,
        streamName: Value(streamName),
        schoolId: schoolId,
        classKey: classKey,
        rootPublicKey: rootPublicKey,
        subjectIdsJson: jsonEncode(subjectIds),
        rosterVersion: roster.version,
        rosterJson: jsonEncode(roster.toJson()),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Updates the cached roster for a delegated class, and this device's own
  /// allocated subjects as of that roster — used when this device syncs
  /// with root and learns of a newer allocation (its own subjects changed,
  /// or another co-teacher's revocation) without a full re-join.
  /// [myPublicKey] is this device's own signing key, used to find its
  /// current entry in [roster] — empty when the roster no longer allocates
  /// this device anything (it's effectively been revoked itself).
  Future<void> updateCachedRoster(
    String classUuid,
    ClassRoster roster,
    String myPublicKey,
  ) async {
    final mine = [
      for (final e in roster.entries)
        if (e.publicKey == myPublicKey) ...e.subjectIds,
    ];
    await (update(coTeachingClasses)
          ..where((t) => t.classGroupUuid.equals(classUuid)))
        .write(
          CoTeachingClassesCompanion(
            rosterVersion: Value(roster.version),
            rosterJson: Value(jsonEncode(roster.toJson())),
            subjectIdsJson: Value(jsonEncode(mine)),
          ),
        );
  }

  Future<void> deleteDelegatedClass(String classUuid) =>
      (delete(coTeachingClasses)
            ..where((t) => t.classGroupUuid.equals(classUuid)))
          .go();
}
