import 'package:drift/drift.dart';

import '../otic_database.dart';
import '../tables/class_groups_table.dart';
import '../tables/students_table.dart';
import '../tables/topic_progress_table.dart';

part 'class_group_dao.g.dart';

/// Classes/streams a teacher creates, and the per-learner numbers the class
/// view is built from.
///
/// Progress is computed on read from `topic_progress` — nothing here stores a
/// second copy of it, so a class rollup can never disagree with the learner
/// detail screen.
@DriftAccessor(tables: [ClassGroups, Students, TopicProgress])
class ClassGroupDao extends DatabaseAccessor<OticDatabase>
    with _$ClassGroupDaoMixin {
  ClassGroupDao(super.db);

  Stream<List<ClassGroup>> watchAllClasses() => (select(classGroups)
        ..orderBy([
          (t) => OrderingTerm.asc(t.className),
          (t) => OrderingTerm.asc(t.streamName),
        ]))
      .watch();

  Future<int> createClass({required String className, String? streamName}) {
    final stream = streamName?.trim();
    return into(classGroups).insert(ClassGroupsCompanion.insert(
      className: className.trim(),
      streamName: Value(stream == null || stream.isEmpty ? null : stream),
    ));
  }

  Future<void> renameClass(int id,
      {required String className, String? streamName}) {
    final stream = streamName?.trim();
    return (update(classGroups)..where((t) => t.id.equals(id))).write(
      ClassGroupsCompanion(
        className: Value(className.trim()),
        streamName: Value(stream == null || stream.isEmpty ? null : stream),
      ),
    );
  }

  /// Deletes a class and unassigns its learners — the learners themselves are
  /// kept. The FK on `students.class_group_id` is not enforced, so without the
  /// explicit update they would point at a class that no longer exists.
  Future<void> deleteClass(int id) => transaction(() async {
        await (update(students)..where((t) => t.classGroupId.equals(id)))
            .write(const StudentsCompanion(classGroupId: Value(null)));
        await (delete(classGroups)..where((t) => t.id.equals(id))).go();
      });

  /// Moves a learner into [classGroupId], or out of any class when null.
  Future<void> assignLearner(int studentId, int? classGroupId) =>
      (update(students)..where((t) => t.id.equals(studentId)))
          .write(StudentsCompanion(classGroupId: Value(classGroupId)));

  /// Topic count, mean mastery and total sessions for every learner, keyed by
  /// student id. One grouped query rather than one per learner.
  Stream<Map<int, LearnerStats>> watchLearnerStats() {
    return customSelect(
      'SELECT s.id AS student_id, '
      '       COUNT(tp.id) AS topics, '
      '       COALESCE(AVG(tp.level), 0.0) AS avg_level, '
      '       COALESCE(SUM(tp.sessions_count), 0) AS sessions '
      'FROM students s '
      'LEFT JOIN topic_progress tp ON tp.student_id = s.id '
      'GROUP BY s.id',
      readsFrom: {students, topicProgress},
    ).watch().map((rows) => {
          for (final r in rows)
            r.read<int>('student_id'): LearnerStats(
              topics: r.read<int>('topics'),
              averageLevel: r.read<double>('avg_level'),
              sessions: r.read<int>('sessions'),
            ),
        });
  }
}

class LearnerStats {
  const LearnerStats({
    required this.topics,
    required this.averageLevel,
    required this.sessions,
  });

  static const empty = LearnerStats(topics: 0, averageLevel: 0, sessions: 0);

  final int topics;

  /// Mean of `topic_progress.level` (0–100) across studied topics.
  final double averageLevel;
  final int sessions;
}
