import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import 'teacher_profiles.dart';

/// What a teacher may do, from the Admin's teaching assignments: upload to
/// a subject they teach, change and share only the materials they
/// uploaded, and only into classes they teach that subject in. Checked
/// here, below the screens.
class TeachingScope {
  TeachingScope(this._db);

  final OticDatabase _db;

  Future<List<TeachingAssignment>> assignments(int teacherId) => (_db.select(
    _db.teachingAssignments,
  )..where((t) => t.teacherId.equals(teacherId))).get();

  Stream<List<TeachingAssignment>> watchAssignments(int teacherId) =>
      (_db.select(
        _db.teachingAssignments,
      )..where((t) => t.teacherId.equals(teacherId))).watch();

  /// Whether [teacherId] teaches [subjectId] — to [classGroupUuid] when
  /// given.
  Future<bool> teaches(
    int? teacherId,
    String subjectId, {
    String? classGroupUuid,
  }) async {
    if (teacherId == null) return false;
    return (await assignments(teacherId)).any(
      (a) =>
          a.subjectId == subjectId &&
          (classGroupUuid == null || a.classGroupUuid == classGroupUuid),
    );
  }

  Future<int?> ownerOf(String subjectId, String documentTitle) async =>
      (await (_db.select(_db.noteOwners)
                ..where((t) => t.subjectId.equals(subjectId))
                ..where((t) => t.documentTitle.equals(documentTitle)))
              .getSingleOrNull())
          ?.teacherId;

  /// Whether [teacherId] may change or remove a note: they teach its
  /// subject and uploaded it. A note nobody owns (its teacher was removed)
  /// is open to whoever teaches the subject.
  Future<bool> mayChangeNote(
    int? teacherId,
    String subjectId,
    String documentTitle,
  ) async {
    if (!await teaches(teacherId, subjectId)) return false;
    final owner = await ownerOf(subjectId, documentTitle);
    return owner == null || owner == teacherId;
  }

  /// Whether [teacherId] may share a note into [classGroupUuid]: they may
  /// change it and teach its subject to that class.
  Future<bool> mayShare(
    int? teacherId,
    String subjectId,
    String documentTitle,
    String classGroupUuid,
  ) async =>
      await mayChangeNote(teacherId, subjectId, documentTitle) &&
      await teaches(teacherId, subjectId, classGroupUuid: classGroupUuid);

  Future<void> recordOwner(
    String subjectId,
    String documentTitle,
    int teacherId,
  ) => _db
      .into(_db.noteOwners)
      .insertOnConflictUpdate(
        NoteOwnersCompanion.insert(
          subjectId: subjectId,
          documentTitle: documentTitle,
          teacherId: teacherId,
        ),
      );

  Future<void> forgetOwner(String subjectId, String documentTitle) =>
      (_db.delete(_db.noteOwners)
            ..where((t) => t.subjectId.equals(subjectId))
            ..where((t) => t.documentTitle.equals(documentTitle)))
          .go();

  /// Every note owner of [subjectId], by document title.
  Stream<Map<String, int>> watchOwners(String subjectId) =>
      (_db.select(_db.noteOwners)..where((t) => t.subjectId.equals(subjectId)))
          .watch()
          .map((rows) => {for (final r in rows) r.documentTitle: r.teacherId});
}

final teachingScopeProvider = Provider<TeachingScope>(
  (ref) => TeachingScope(ref.watch(dbProvider)),
);

/// The signed-in teacher's assignments, live.
final myAssignmentsProvider = StreamProvider<List<TeachingAssignment>>((ref) {
  final me = ref.watch(activeTeacherIdProvider);
  if (kIsWeb || me == null) return Stream.value(const []);
  return ref.watch(teachingScopeProvider).watchAssignments(me);
});

/// Note owners of one subject, by document title.
final noteOwnersProvider = StreamProvider.family<Map<String, int>, String>((
  ref,
  subjectId,
) {
  if (kIsWeb) return Stream.value(const {});
  return ref.watch(teachingScopeProvider).watchOwners(subjectId);
});
