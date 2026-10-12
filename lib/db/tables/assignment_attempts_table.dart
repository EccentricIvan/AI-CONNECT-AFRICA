import 'package:drift/drift.dart';

import 'students_table.dart';

/// A learner's timed assessment in progress (schema 32): when they started
/// it and what they have typed so far, so leaving the screen or closing the
/// app neither restarts the clock nor loses the work. When time runs out,
/// the draft is submitted as it stands.
@DataClassName('AssignmentAttempt')
class AssignmentAttempts extends Table {
  @override
  String get tableName => 'assignment_attempts';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get assignmentId => text()();

  /// ISO-8601 UTC, this device's clock.
  TextColumn get startedAt => text()();
  TextColumn get draft => text().withDefault(const Constant(''))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {studentId, assignmentId},
  ];
}
