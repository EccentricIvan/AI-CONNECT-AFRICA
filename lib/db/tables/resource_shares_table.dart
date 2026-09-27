import 'package:drift/drift.dart';

/// Which class/stream receives which teacher note. A note is a
/// (subject, document) pair — one uploaded file or typed note, the same
/// thing the teacher sees in their list, however it was split inside.
///
/// Sharing is opt-in per note: a note with no row here is never served to
/// any device, whichever class asks.
@TableIndex(
  name: 'idx_resource_shares_unique',
  columns: {#subjectId, #documentTitle, #classGroupUuid},
  unique: true,
)
class ResourceShares extends Table {
  @override
  String get tableName => 'resource_shares';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get subjectId => text()();

  /// `COALESCE(topic_resources.document_title, resource_title)` of the note.
  TextColumn get documentTitle => text()();

  /// [ClassGroups.groupUuid] of a class this device created.
  TextColumn get classGroupUuid => text()();
}
