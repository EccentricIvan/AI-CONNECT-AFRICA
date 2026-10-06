import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import 'teacher_pin.dart';

/// Teachers who sign in on this device, each with their own PIN.
///
/// The Teachers PIN ([TeacherPin]) opens the Teachers area; there a teacher
/// signs in to their profile or creates one. What a teacher creates —
/// classes, streams, subjects, and the materials inside their subjects — is
/// theirs: only they may change it. Like the Teachers PIN, this keeps
/// people apart on a shared device; it is not real security.
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

  /// Creates a profile. The first one on a device takes over every class,
  /// stream and subject made here before profiles existed.
  Future<TeacherProfileResult> create({
    required String name,
    required String pin,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const TeacherProfileResult.failed('Enter a name.');
    if (!TeacherPin.isValidFormat(pin)) {
      return const TeacherProfileResult.failed('A PIN is 4 to 8 digits.');
    }
    final existing = await all();
    if (existing.any((t) => t.name.toLowerCase() == trimmed.toLowerCase())) {
      return const TeacherProfileResult.failed('That name is taken.');
    }
    final salt = newPinSalt();
    return _db.transaction(() async {
      final id = await _db
          .into(_db.teacherProfiles)
          .insert(
            TeacherProfilesCompanion.insert(
              name: trimmed,
              pinSalt: salt,
              pinHash: hashPin(salt, pin),
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
      if (existing.isEmpty) await claimUnowned(id);
      final row = await (_db.select(
        _db.teacherProfiles,
      )..where((t) => t.id.equals(id))).getSingle();
      return TeacherProfileResult(row);
    });
  }

  /// Gives [teacherId] every class, stream and subject made on this device
  /// that has no owner: those from before profiles existed, or taken over
  /// from a host device (failover).
  Future<void> claimUnowned(int teacherId) async {
    await (_db.update(_db.classGroups)
          ..where((t) => t.ownerTeacherId.isNull() & t.joined.equals(false)))
        .write(ClassGroupsCompanion(ownerTeacherId: Value(teacherId)));
    await (_db.update(_db.customSubjects)..where(
          (t) => t.ownerTeacherId.isNull() & t.classGroupUuid.isNull(),
        ))
        .write(CustomSubjectsCompanion(ownerTeacherId: Value(teacherId)));
    await (_db.update(_db.coTeachingClasses)
          ..where((t) => t.ownerTeacherId.isNull()))
        .write(CoTeachingClassesCompanion(ownerTeacherId: Value(teacherId)));
  }

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

class TeacherProfileResult {
  const TeacherProfileResult(this.profile) : error = null;
  const TeacherProfileResult.failed(this.error) : profile = null;

  final TeacherProfile? profile;
  final String? error;
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
