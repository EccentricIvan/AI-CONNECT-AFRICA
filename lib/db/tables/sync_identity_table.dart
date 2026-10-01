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

  // ── Host failover (lib/collaboration/sync/p2p_failover_service.dart) ──

  /// How many times this school's host identity has been taken over by a
  /// standby. Every served channel and roster version this device signs
  /// sits at or above `hostGeneration << 32`, so anything a replaced host
  /// signs afterwards is older than what students already hold. Handshakes
  /// carry it as `host_epoch`, so students refuse a superseded host.
  IntColumn get hostGeneration => integer().withDefault(const Constant(0))();

  /// Host device with a standby: the AES key stretched from the teacher's
  /// failover passphrase, with its salt and PBKDF2 rounds. Kept so the
  /// ledger can be re-sealed on every pull without asking again. It
  /// exposes nothing [signingSeed] doesn't already: both sit in this
  /// database in the clear.
  TextColumn get failoverSealKey => text().nullable()();
  TextColumn get failoverKdfSalt => text().nullable()();
  IntColumn get failoverKdfRounds => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

const kRoleTeacher = 'teacher';
const kRoleStudent = 'student';
