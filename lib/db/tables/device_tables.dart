import 'package:drift/drift.dart';

/// Teacher side: the devices that joined one of this device's classes, by
/// their keys. A revoked one is refused on every request, and the class
/// key is replaced so it can't read anything sent afterwards.
@DataClassName('ClassMember')
@TableIndex(
  name: 'idx_class_members_device',
  columns: {#classGroupUuid, #deviceKey},
  unique: true,
)
class ClassMembers extends Table {
  @override
  String get tableName => 'class_members';

  IntColumn get id => integer().autoIncrement()();

  /// `class_groups.group_uuid`.
  TextColumn get classGroupUuid => text()();

  /// The device's Ed25519 public key.
  TextColumn get deviceKey => text()();

  /// Its X25519 public key; null for a device on an older build, which
  /// must join again once the class key changes.
  TextColumn get boxKey => text().nullable()();

  /// The learner name it joined with.
  TextColumn get name => text().withDefault(const Constant(''))();

  /// ISO-8601 UTC.
  TextColumn get joinedAt => text()();
  TextColumn get lastSeenAt => text().nullable()();

  /// ISO-8601 UTC; null while trusted.
  TextColumn get revokedAt => text().nullable()();
}

/// Devices the Admin revoked for the whole school, from the Admin's
/// records (or made here, on the Admin's own device). Every Sync on every
/// device refuses them.
@DataClassName('RevokedDevice')
class RevokedDevices extends Table {
  @override
  String get tableName => 'revoked_devices';

  /// Ed25519 public key.
  TextColumn get deviceKey => text()();
  TextColumn get name => text().withDefault(const Constant(''))();

  /// ISO-8601 UTC.
  TextColumn get revokedAt => text()();

  @override
  Set<Column> get primaryKey => {deviceKey};
}

/// Admin side: devices that took the school's records, so the Admin can
/// revoke one for the whole school.
@DataClassName('SchoolDevice')
class SchoolDevices extends Table {
  @override
  String get tableName => 'school_devices';

  /// Ed25519 public key.
  TextColumn get deviceKey => text()();
  TextColumn get name => text().withDefault(const Constant(''))();

  /// ISO-8601 UTC.
  TextColumn get registeredAt => text()();

  @override
  Set<Column> get primaryKey => {deviceKey};
}

/// Teacher side: which version of each class+subject a member device
/// says it holds, from its last sync. Lesson materials counts the devices
/// holding the current version: "On N devices".
@DataClassName('ChannelReceipt')
class ChannelReceipts extends Table {
  @override
  String get tableName => 'channel_receipts';

  TextColumn get classGroupUuid => text()();
  TextColumn get subjectId => text()();

  /// Ed25519 public key of the device.
  TextColumn get deviceKey => text()();
  IntColumn get version => integer()();

  /// ISO-8601 UTC.
  TextColumn get receivedAt => text()();

  @override
  Set<Column> get primaryKey => {classGroupUuid, subjectId, deviceKey};
}
