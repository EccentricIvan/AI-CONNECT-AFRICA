import 'package:drift/drift.dart';

/// This device's school and its class-sync signing key. One row at most.
///
/// The school is set by the Admin on a teacher's device, and adopted from the
/// teacher at a student device's first class join. The signing seed is this
/// device's Ed25519 private key; its public half is what student devices pin.
class SyncIdentity extends Table {
  @override
  String get tableName => 'sync_identity';

  IntColumn get id => integer()();
  TextColumn get schoolId => text().nullable()();
  TextColumn get schoolName => text().nullable()();
  TextColumn get signingSeed => text()();

  /// What this device is to its school: [kRoleTeacher], [kRoleStudent], or
  /// null until it becomes one. The teacher device is where classes and
  /// subjects are made and students' progress arrives; a device becomes a
  /// student device when it joins a class through a teacher, and then can't
  /// create classes or subjects or claim the teacher role.
  TextColumn get deviceRole => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

const kRoleTeacher = 'teacher';
const kRoleStudent = 'student';
