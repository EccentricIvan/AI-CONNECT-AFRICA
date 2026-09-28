import 'package:drift/drift.dart';

/// One row per (class/stream, subject) channel this device has pulled from
/// a teacher (or a classmate passing the teacher's notes on).
///
/// Lives on the receiving device. A student sharing with classmates reads
/// it to hand on the teacher's signed manifests unchanged; a teacher's
/// device keeps its own versions in `ServedChannels` instead.
@TableIndex(
  name: 'idx_sync_state_channel',
  columns: {#classGroupUuid, #subjectId},
  unique: true,
)
class SyncState extends Table {
  @override
  String get tableName => 'sync_state';

  IntColumn get id => integer().autoIncrement()();

  /// [ClassGroups.groupUuid] this channel is scoped to.
  TextColumn get classGroupUuid => text()();
  TextColumn get subjectId => text()();

  /// ISO-8601 UTC — the newest `topic_resources.updatedAt` this device has
  /// already ingested for this channel. The next `/sync/channel` request
  /// asks for anything newer than this, so a repeat sync only moves what
  /// changed since the last one.
  TextColumn get lastSyncedAt => text()();

  /// Chunks this device has rejected on this channel (bad hash, malformed
  /// routing key, …) across every sync so far — surfaced in the sync UI so
  /// a persistently high count is visible instead of silently swallowed.
  IntColumn get rejectedCount => integer().withDefault(const Constant(0))();

  /// The channel digest (see `channelDigest`) this device last replaced its
  /// copy of the channel with. The next sync skips the channel while the
  /// teacher's digest still matches. Null on a tombstone: a subject the
  /// teacher stopped sharing, kept so a classmate can't bring it back.
  TextColumn get channelDigest => text().nullable()();

  /// The teacher's version of this channel (see `ServedChannels`). A copy
  /// relayed by a classmate is taken only when its version is higher.
  IntColumn get channelVersion => integer().nullable()();

  /// The teacher's signature over this channel's manifest — kept so this
  /// device can pass the channel on and the next device can check it came
  /// from the teacher unchanged.
  TextColumn get manifestSig => text().nullable()();
}
