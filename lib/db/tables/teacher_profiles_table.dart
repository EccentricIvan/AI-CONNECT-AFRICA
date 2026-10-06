import 'package:drift/drift.dart';

/// A teacher who signs in on this device with their own PIN.
///
/// Every device can do teacher duties. The Teachers PIN (`TeacherPin`)
/// opens the Teachers area; each teacher then signs in to their profile,
/// and the classes, streams and subjects they create are theirs alone to
/// change (`owner_teacher_id` on those tables). Local only, never synced.
@DataClassName('TeacherProfile')
class TeacherProfiles extends Table {
  @override
  String get tableName => 'teacher_profiles';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Salted SHA-256 of the teacher's PIN; the PIN itself is never stored.
  TextColumn get pinSalt => text()();
  TextColumn get pinHash => text()();

  /// ISO-8601 UTC.
  TextColumn get createdAt => text()();
}
