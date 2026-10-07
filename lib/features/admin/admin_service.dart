import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/sync/sync_ids.dart';
import '../../collaboration/sync/device_registry.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../services/custom_subject_service.dart';
import '../../services/learner_data_wiper.dart';
import '../../services/offline_storage_service.dart';
import '../teacher/teacher_pin.dart';
import '../teacher/teacher_profiles.dart' show kSessionLife;
import '../teacher/teaching_scope.dart';

/// Proof that the Admin signed in with their PIN. Only [AdminService] makes
/// one, and every change to the school's records needs it — the rule is
/// enforced here, below the screens.
class AdminSession {
  AdminSession._(this.name);
  final String name;
}

/// The school's one Admin and the records only they change: teachers,
/// classes and streams, subjects, teaching assignments, learners and their
/// enrolments.
///
/// Like the other PINs, the Admin PIN keeps people apart on a shared
/// device; it is not real security.
class AdminService {
  AdminService(this._db, this._subjects, this._wiper);

  final OticDatabase _db;
  final CustomSubjectService _subjects;
  final LearnerDataWiper _wiper;

  Future<AdminIdentityRow?> _row() => (_db.select(
    _db.adminIdentity,
  )..where((t) => t.id.equals(1))).getSingleOrNull();

  Future<bool> isSetUp() async => await _row() != null;

  /// Sets up this device's Admin. Refused once one exists, and on a device
  /// that holds another Admin's school records: a school has one Admin,
  /// who takes over there with their passphrase instead.
  Future<AdminSession?> setUp({
    required String name,
    required String pin,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || !TeacherPin.isValidFormat(pin)) return null;
    if (await isSetUp()) return null;
    if (await (_db.select(
          _db.adminRecordsState,
        )..where((t) => t.id.equals(1))).getSingleOrNull() !=
        null) {
      return null;
    }
    final salt = newPinSalt();
    await _db
        .into(_db.adminIdentity)
        .insert(
          AdminIdentityCompanion.insert(
            id: const Value(1),
            name: trimmed,
            pinSalt: salt,
            pinHash: await hashPinStrong(salt, pin),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
    return AdminSession._(trimmed);
  }

  Future<AdminSession?> signIn(String pin) async {
    final row = await _row();
    if (row == null || !await pinMatches(row.pinSalt, pin, row.pinHash)) {
      return null;
    }
    if (pinNeedsUpgrade(row.pinHash)) {
      await (_db.update(_db.adminIdentity)..where((t) => t.id.equals(1))).write(
        AdminIdentityCompanion(
          pinHash: Value(await hashPinStrong(row.pinSalt, pin)),
        ),
      );
    }
    return AdminSession._(row.name);
  }

  Future<bool> changePin(AdminSession _, String current, String next) async {
    if (!TeacherPin.isValidFormat(next)) return false;
    final row = await _row();
    if (row == null ||
        !await pinMatches(row.pinSalt, current, row.pinHash)) {
      return false;
    }
    final salt = newPinSalt();
    await (_db.update(_db.adminIdentity)..where((t) => t.id.equals(1))).write(
      AdminIdentityCompanion(
        pinSalt: Value(salt),
        pinHash: Value(await hashPinStrong(salt, next)),
      ),
    );
    return true;
  }

  // ── Teachers ──────────────────────────────────────────────────────────

  /// Adds a teacher who signs in with [pin]. Null with a reason when the
  /// name is empty or taken, or the PIN is not 4 to 8 digits.
  Future<String?> addTeacher(
    AdminSession _, {
    required String name,
    required String pin,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name.';
    if (!TeacherPin.isValidFormat(pin)) return 'A PIN is 4 to 8 digits.';
    final taken = await (_db.select(
      _db.teacherProfiles,
    )..where((t) => t.name.lower().equals(trimmed.toLowerCase()))).get();
    if (taken.isNotEmpty) return 'That name is taken.';
    final salt = newPinSalt();
    await _db
        .into(_db.teacherProfiles)
        .insert(
          TeacherProfilesCompanion.insert(
            name: trimmed,
            pinSalt: salt,
            pinHash: await hashPinStrong(salt, pin),
            createdAt: DateTime.now().toUtc().toIso8601String(),
            uuid: Value(newSyncId()),
          ),
        );
    return null;
  }

  /// Sets a teacher's PIN — for one who forgot theirs.
  Future<bool> resetTeacherPin(AdminSession _, int teacherId, String pin) async {
    if (!TeacherPin.isValidFormat(pin)) return false;
    final salt = newPinSalt();
    final n = await (_db.update(
      _db.teacherProfiles,
    )..where((t) => t.id.equals(teacherId))).write(
      TeacherProfilesCompanion(
        pinSalt: Value(salt),
        pinHash: Value(await hashPinStrong(salt, pin)),
      ),
    );
    return n > 0;
  }

  /// Classes stop being served what their assignments no longer cover.
  Future<void> _prune() => TeachingScope(_db).pruneShares();

  /// Removes a teacher and their assignments. Their notes stay, owned by
  /// nobody, for whoever the Admin assigns next.
  Future<void> removeTeacher(AdminSession _, int teacherId) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.teachingAssignments,
        )..where((t) => t.teacherId.equals(teacherId))).go();
        await (_db.delete(
          _db.noteOwners,
        )..where((t) => t.teacherId.equals(teacherId))).go();
        await (_db.delete(
          _db.teacherProfiles,
        )..where((t) => t.id.equals(teacherId))).go();
        await _prune();
      });

  // ── Classes and streams ───────────────────────────────────────────────

  Future<int> addClass(
    AdminSession _, {
    required String className,
    String? streamName,
  }) => _db.classGroupDao.createClass(
    className: className,
    streamName: streamName,
  );

  Future<void> renameClass(
    AdminSession _,
    int id, {
    required String className,
    String? streamName,
  }) => _db.classGroupDao.renameClass(
    id,
    className: className,
    streamName: streamName,
  );

  /// Deletes a class, its assignments and its enrolments. Learners stay.
  Future<void> deleteClass(AdminSession _, ClassGroup group) =>
      _db.transaction(() async {
        final uuid = group.groupUuid;
        if (uuid != null) {
          await (_db.delete(
            _db.teachingAssignments,
          )..where((t) => t.classGroupUuid.equals(uuid))).go();
          await (_db.delete(
            _db.studentEnrolments,
          )..where((t) => t.classGroupUuid.equals(uuid))).go();
        }
        await _db.classGroupDao.deleteClass(group.id);
      });

  // ── Subjects ──────────────────────────────────────────────────────────

  Future<CustomSubjectResult> addSubject(AdminSession _, String name) =>
      _subjects.create(name: name);

  Future<void> renameSubject(AdminSession _, String subjectId, String name) =>
      _subjects.rename(subjectId, name);

  /// Deletes a subject, its materials and its assignments.
  Future<void> deleteSubject(AdminSession _, String subjectId) async {
    final id = normalizeSubjectId(subjectId);
    await (_db.delete(
      _db.teachingAssignments,
    )..where((t) => t.subjectId.equals(id))).go();
    await (_db.delete(
      _db.noteOwners,
    )..where((t) => t.subjectId.equals(id))).go();
    await _subjects.delete(id);
  }

  // ── Teaching assignments ──────────────────────────────────────────────

  /// Assigns [teacherId] to teach [subjectId] to a class/stream. False
  /// when that teacher already has it.
  Future<bool> assign(
    AdminSession _, {
    required int teacherId,
    required String classGroupUuid,
    required String subjectId,
    required int academicYear,
    int term = 0,
  }) async {
    final existing =
        await (_db.select(_db.teachingAssignments)
              ..where((t) => t.teacherId.equals(teacherId))
              ..where((t) => t.classGroupUuid.equals(classGroupUuid))
              ..where((t) => t.subjectId.equals(subjectId))
              ..where((t) => t.academicYear.equals(academicYear))
              ..where((t) => t.term.equals(term)))
            .get();
    if (existing.isNotEmpty) return false;
    await _db
        .into(_db.teachingAssignments)
        .insert(
          TeachingAssignmentsCompanion.insert(
            uuid: newSyncId(),
            teacherId: teacherId,
            classGroupUuid: classGroupUuid,
            subjectId: subjectId,
            academicYear: academicYear,
            term: Value(term),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
    return true;
  }

  Future<void> unassign(AdminSession _, int assignmentId) async {
    await (_db.delete(
      _db.teachingAssignments,
    )..where((t) => t.id.equals(assignmentId))).go();
    await _prune();
  }

  // ── Learners and enrolments ───────────────────────────────────────────

  Future<int?> addLearner(AdminSession _, {required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    return _db.studentDao.createStudent(
      StudentsCompanion.insert(name: trimmed, uuid: Value(newSyncId())),
    );
  }

  /// Enrols a learner in a class/stream for [academicYear]; their earlier
  /// active enrolment is withdrawn, never deleted.
  Future<void> enrol(
    AdminSession _, {
    required int studentId,
    required ClassGroup group,
    required int academicYear,
  }) => _db.transaction(() async {
    final uuid = group.groupUuid;
    if (uuid == null) return;
    await (_db.update(_db.studentEnrolments)
          ..where((t) => t.studentId.equals(studentId))
          ..where((t) => t.status.equals('active')))
        .write(const StudentEnrolmentsCompanion(status: Value('withdrawn')));
    await _db
        .into(_db.studentEnrolments)
        .insert(
          StudentEnrolmentsCompanion.insert(
            uuid: newSyncId(),
            studentId: studentId,
            classGroupUuid: uuid,
            academicYear: academicYear,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
    await _db.classGroupDao.assignLearner(studentId, group.id);
  });

  /// Withdraws a learner from their class.
  Future<void> withdraw(AdminSession _, int studentId) =>
      _db.transaction(() async {
        await (_db.update(_db.studentEnrolments)
              ..where((t) => t.studentId.equals(studentId))
              ..where((t) => t.status.equals('active')))
            .write(
              const StudentEnrolmentsCompanion(status: Value('withdrawn')),
            );
        await _db.classGroupDao.assignLearner(studentId, null);
      });

  /// Deletes a learner and everything scoped to them.
  Future<void> deleteLearner(AdminSession _, int studentId) =>
      _wiper.wipeStudent(studentId);

  /// Deletes every learner's data on this device.
  Future<void> resetAllLearners(AdminSession _) => _wiper.wipeAll();

  // ── Devices ───────────────────────────────────────────────────────────

  /// Revokes a device for the whole school. It reaches other devices with
  /// the next records the Admin sends; each then refuses it and replaces
  /// the key of every class it held.
  Future<void> revokeDevice(
    AdminSession _,
    String deviceKey, {
    String name = '',
  }) => DeviceRegistry(_db).revokeSchoolWide(deviceKey, name: name);
}

final adminServiceProvider = Provider<AdminService>(
  (ref) => AdminService(
    ref.watch(dbProvider),
    ref.watch(customSubjectServiceProvider),
    ref.watch(learnerDataWiperProvider),
  ),
);

/// The Admin's session while signed in, or null. In memory only; cleared
/// whenever the device is handed to a learner, and [kSessionLife] after
/// signing in.
final adminSessionProvider = StateProvider<AdminSession?>((ref) {
  Timer? expiry;
  ref.onDispose(() => expiry?.cancel());
  ref.listenSelf((_, next) {
    expiry?.cancel();
    if (next != null) {
      expiry = Timer(kSessionLife, () => ref.controller.state = null);
    }
  });
  return null;
});

final adminSetUpProvider = FutureProvider.autoDispose<bool>((ref) {
  if (kIsWeb) return Future.value(false);
  return ref.watch(adminServiceProvider).isSetUp();
});
