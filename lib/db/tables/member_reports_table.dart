import 'package:drift/drift.dart';

/// Teacher device only: the latest progress summary each class member's
/// device sent, one row per learner.
///
/// A student device sends it whenever it syncs with the teacher (see
/// `progress_report.dart`). Compressed summaries only — totals, per-topic
/// mastery, strengths/weaknesses — never conversations. Replaced whole on
/// each report, so a learner's row is always their latest state.
@TableIndex(
  name: 'idx_member_reports_member',
  columns: {#classGroupUuid, #memberKey},
  unique: true,
)
class MemberReports extends Table {
  @override
  String get tableName => 'member_reports';

  IntColumn get id => integer().autoIncrement()();

  /// The class/stream reported to ([ClassGroups.groupUuid]).
  TextColumn get classGroupUuid => text()();

  /// Stable per learner per device: the device's public key + its local
  /// learner id. Two learners sharing one device stay two rows.
  TextColumn get memberKey => text()();

  TextColumn get name => text()();

  /// The summary as the device sent it (`ProgressReport.toJson`).
  TextColumn get reportJson => text()();

  /// ISO-8601 UTC, this (teacher) device's clock.
  TextColumn get receivedAt => text()();
}
