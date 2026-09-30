import 'package:drift/drift.dart';

import 'students_table.dart';

/// Subjects a learner says they take — a record the teacher sees in Class
/// progress. It doesn't hide or unlock anything: every subject stays open
/// to every learner.
@TableIndex(
  name: 'idx_learner_subjects_unique',
  columns: {#studentId, #subjectId},
  unique: true,
)
class LearnerSubjects extends Table {
  @override
  String get tableName => 'learner_subjects';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get subjectId => text()();

  /// ISO-8601 UTC.
  TextColumn get enrolledAt => text()();
}
