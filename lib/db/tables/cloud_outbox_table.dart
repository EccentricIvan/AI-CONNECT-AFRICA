import 'package:drift/drift.dart';

/// Records waiting for the school cloud plug-in (schema 32,
/// `lib/collaboration/cloud/`). A row only names a record (kind + uuid);
/// its content is read from its own table when it is sent, so nothing is
/// stored twice and a record deleted meanwhile (a wiped learner) is
/// dropped, not sent.
@DataClassName('CloudOutboxEntry')
class CloudOutbox extends Table {
  @override
  String get tableName => 'cloud_outbox';

  IntColumn get id => integer().autoIncrement()();

  /// Stable id the cloud de-duplicates on, e.g. `submission:<uuid>` or
  /// `grade:<uuid>:<version>`.
  TextColumn get recordId => text().unique()();
  TextColumn get kind => text()();
  TextColumn get refUuid => text()();

  /// ISO-8601 UTC.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC: the cloud accepted it. Null until then.
  TextColumn get sentAt => text().nullable()();
}
