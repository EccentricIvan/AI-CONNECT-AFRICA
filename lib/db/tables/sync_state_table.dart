import 'package:drift/drift.dart';

/// One row per (class/stream, subject) channel this device has pulled from
/// a teacher's sync server — the local half of "last_sync_timestamp".
///
/// Lives on the pulling device only. A teacher's device never reads this
/// table; [TeacherSyncServer] is stateless per request, computing its
/// answer straight from `topic_resources` each time.
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
}
