import 'package:drift/drift.dart';

import 'students_table.dart';

/// One finished quiz round on one topic, for one learner — what the
/// Achievements screen shows as quiz scores. A round over several topics
/// is stored as one row per topic.
@TableIndex(name: 'idx_quiz_results_student', columns: {#studentId, #subjectId})
class QuizResults extends Table {
  @override
  String get tableName => 'quiz_results';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get subjectId => text()();

  /// The note's topic (section heading), or the subject's name for
  /// questions with no topic.
  TextColumn get topic => text()();
  IntColumn get correct => integer()();
  IntColumn get total => integer()();

  /// ISO-8601 UTC.
  TextColumn get takenAt => text()();
}
