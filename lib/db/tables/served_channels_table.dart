import 'package:drift/drift.dart';

/// Teacher device only: the version of each (class/stream, subject) channel
/// it has served.
///
/// A student device can pass the teacher's notes on to a classmate, so a
/// channel's copy can arrive from someone other than the teacher, possibly
/// an old one. The teacher signs each channel with a [version] that only
/// ever goes up — bumped whenever the channel's digest changes, including
/// when the subject stops being shared (digest null) — and a receiver takes
/// a relayed copy only if it is newer than what it has. Without this, a
/// classmate holding last month's notes could quietly roll a friend back.
@TableIndex(
  name: 'idx_served_channels_channel',
  columns: {#classGroupUuid, #subjectId},
  unique: true,
)
class ServedChannels extends Table {
  @override
  String get tableName => 'served_channels';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get classGroupUuid => text()();
  TextColumn get subjectId => text()();

  /// The channel digest last served; null once the subject stopped being
  /// shared with the class.
  TextColumn get digest => text().nullable()();

  IntColumn get version => integer()();
}
