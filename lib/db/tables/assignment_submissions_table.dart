import 'package:drift/drift.dart';

/// A learner's answer to a teacher's class assignment, and the teacher's
/// grade for it — on the learner's device and, after Sync, the teacher's.
///
/// Two owners, never overwriting each other:
/// - the learner owns the answer: a row is written once with a stable
///   [uuid] and never changed (a new answer is a new row), and [createdAt]
///   keeps when it was made, apart from when it reached the teacher
///   ([receivedAt]);
/// - the teacher owns the grade: [grade], [feedback] and [gradedAt] change
///   only with a higher [gradeVersion].
///
/// So retrying a sync, or receiving the same row twice, changes nothing.
@DataClassName('AssignmentSubmission')
@TableIndex(name: 'idx_submissions_assignment', columns: {#assignmentId})
class AssignmentSubmissions extends Table {
  @override
  String get tableName => 'assignment_submissions';

  IntColumn get id => integer().autoIncrement()();

  /// Stable operation id, minted on the learner's device.
  TextColumn get uuid => text().unique()();

  /// The assignment's id (inside its `~assignment` note row).
  TextColumn get assignmentId => text()();
  TextColumn get subjectId => text()();

  /// On the learner's device: `students.id`. Null on the teacher's device,
  /// where the learner is known by [memberKey] and [learnerName].
  IntColumn get studentId => integer().nullable()();

  /// The learner as their device reports them (`deviceKey/studentId`).
  TextColumn get memberKey => text()();
  TextColumn get learnerName => text()();

  TextColumn get answer => text()();

  /// ISO-8601 UTC: made on the learner's device (its clock).
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC: reached the teacher's device. Null until then.
  TextColumn get receivedAt => text().nullable()();

  IntColumn get grade => integer().nullable()();
  TextColumn get feedback => text().nullable()();
  IntColumn get gradeVersion => integer().withDefault(const Constant(0))();

  /// ISO-8601 UTC.
  TextColumn get gradedAt => text().nullable()();
}
