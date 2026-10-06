import 'package:drift/drift.dart';

import 'students_table.dart';

/// Subjects a learner says they take — a record the teacher sees in Class
/// progress. On a student device it also decides which subjects' notes
/// (text and PDFs) the learner may read; lessons stay open to everyone.
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
