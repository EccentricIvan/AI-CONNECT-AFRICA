import 'package:drift/drift.dart';

/// Host (root teacher) device only: devices the teacher paired as a standby
/// that can take over if this device dies. One row per standby, pinned by
/// its Ed25519 public key at pairing (code + the teacher's Accept) — only
/// these keys may pull the encrypted host ledger
/// (`lib/collaboration/sync/p2p_failover_service.dart`).
@TableIndex(
  name: 'idx_failover_standbys_key',
  columns: {#publicKey},
  unique: true,
)
class FailoverStandbys extends Table {
  @override
  String get tableName => 'failover_standbys';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get publicKey => text()();

  /// Name the standby typed when pairing — shown on the teacher's screen.
  TextColumn get name => text()();
  DateTimeColumn get pairedAt => dateTime().withDefault(currentDateAndTime)();

  /// When the standby last pulled a ledger. Null until its first pull.
  DateTimeColumn get lastMirroredAt => dateTime().nullable()();
}

/// Standby device only: the newest host ledger it holds for the one host it
/// is standing by for. At most one row (id 1).
///
/// [sealedJson] is encrypted under a key stretched from the teacher's
/// passphrase, which this device never learns until someone types it at
/// promotion. The ledger includes the host's signing key, so this row is as
/// sensitive as the host itself, guarded only by the passphrase's strength.
class HostLedgers extends Table {
  @override
  String get tableName => 'host_ledgers';

  IntColumn get id => integer()();

  /// The host's Ed25519 public key, pinned at pairing. A ledger reply not
  /// signed by it is never stored.
  TextColumn get rootPublicKey => text()();
  TextColumn get schoolId => text()();
  TextColumn get schoolName => text()();

  /// Null between pairing and the first successful pull.
  TextColumn get sealedJson => text().nullable()();

  /// The ledger's host generation (see `SyncIdentity.hostGeneration`).
  IntColumn get generation => integer().withDefault(const Constant(0))();
  DateTimeColumn get receivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
