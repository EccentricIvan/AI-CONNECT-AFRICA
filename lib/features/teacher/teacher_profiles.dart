import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import 'teacher_pin.dart';

/// Teachers who sign in on this device, each with their own PIN.
///
/// The Admin adds teachers (`AdminService.addTeacher`); the Teachers PIN
/// ([TeacherPin]) opens the Teachers area, where each signs in. What a
/// teacher may do follows from the Admin's teaching assignments
/// (`TeachingScope`). Like the other PINs, this keeps people apart on a
/// shared device; it is not real security.
class TeacherProfileService {
  TeacherProfileService(this._db);

  final OticDatabase _db;

  Stream<List<TeacherProfile>> watchAll() =>
      (_db.select(_db.teacherProfiles)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<TeacherProfile>> all() =>
      (_db.select(_db.teacherProfiles)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  /// The profile when [pin] is its PIN, else null.
  Future<TeacherProfile?> signIn(int teacherId, String pin) async {
    final row = await (_db.select(
      _db.teacherProfiles,
    )..where((t) => t.id.equals(teacherId))).getSingleOrNull();
    if (row == null) return null;
    return hashPin(row.pinSalt, pin) == row.pinHash ? row : null;
  }

  /// Changes [teacherId]'s PIN; false when [current] is wrong.
  Future<bool> changePin(int teacherId, String current, String next) async {
    if (!TeacherPin.isValidFormat(next)) return false;
    if (await signIn(teacherId, current) == null) return false;
    final salt = newPinSalt();
    await (_db.update(
      _db.teacherProfiles,
    )..where((t) => t.id.equals(teacherId))).write(
      TeacherProfilesCompanion(
        pinSalt: Value(salt),
        pinHash: Value(hashPin(salt, next)),
      ),
    );
    return true;
  }
}

final teacherProfileServiceProvider = Provider<TeacherProfileService>(
  (ref) => TeacherProfileService(ref.watch(dbProvider)),
);

final teacherProfilesProvider = StreamProvider<List<TeacherProfile>>((ref) {
  if (kIsWeb) return Stream.value(const []);
  return ref.watch(teacherProfileServiceProvider).watchAll();
});

/// The teacher signed in on this device, or null.
///
/// In memory only, so nobody is signed in after a restart. Cleared with
/// [teacherUnlockedProvider] whenever the device is handed to a learner.
final activeTeacherProvider = StateProvider<TeacherProfile?>((ref) => null);

/// The signed-in teacher's id, or null.
final activeTeacherIdProvider = Provider<int?>(
  (ref) => ref.watch(activeTeacherProvider)?.id,
);
