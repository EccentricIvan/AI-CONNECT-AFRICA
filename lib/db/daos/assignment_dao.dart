import 'package:drift/drift.dart';
import '../otic_database.dart';
import '../tables/assignments_table.dart';

part 'assignment_dao.g.dart';

/// One student's assigned/completed counts and points for one subject,
/// rolled up across every term — "rolling, year-long" as opposed to any
/// one term's slice.
class SubjectYearProgress {
  const SubjectYearProgress({
    required this.assigned,
    required this.completed,
    required this.points,
  });

  final int assigned;
  final int completed;

  /// Sum of `point_value` for completed assignments only — outstanding
  /// work contributes nothing until [AssignmentDao.completedAt] is set.
  final int points;

  /// 0.0–1.0. 0 when nothing has been assigned yet, rather than dividing
  /// by zero or reading as 100% complete.
  double get progress => assigned == 0 ? 0.0 : completed / assigned;
}

@DriftAccessor(tables: [Assignments])
class AssignmentDao extends DatabaseAccessor<OticDatabase>
    with _$AssignmentDaoMixin {
  AssignmentDao(super.db);

  Future<int> assign({
    required int studentId,
    required String subjectId,
    required int termMarker,
    required String title,
    int pointValue = 10,
    DateTime? assignedAt,
  }) {
    assert(kAssignmentTermMarkers.contains(termMarker),
        'termMarker must be 1, 2 or 3 — an assignment always belongs to '
        'exactly one term.');
    return into(assignments).insert(
      AssignmentsCompanion.insert(
        studentId: studentId,
        subjectId: subjectId,
        termMarker: termMarker,
        title: title,
        pointValue: Value(pointValue),
        assignedAt: (assignedAt ?? DateTime.now()).toUtc().toIso8601String(),
      ),
    );
  }

  Future<Assignment?> byId(int id) =>
      (select(assignments)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Marks one assignment done. Does **not** touch student points — that is
  /// [AcademicScoreTrackerRepository.markCompleted]'s job, so a point award
  /// can never happen without going through the one method that also makes
  /// it atomic with the profile update.
  Future<void> setCompleted(int id, DateTime completedAt) =>
      (update(assignments)..where((t) => t.id.equals(id))).write(
        AssignmentsCompanion(
          completedAt: Value(completedAt.toUtc().toIso8601String()),
        ),
      );

  /// One term's assignments for one student+subject — the "distinct
  /// multi-term" query: 'Term 1' / 'Term 2' / 'Term 3' each answered
  /// separately, never blended with the others.
  Future<List<Assignment>> forTerm({
    required int studentId,
    required String subjectId,
    required int termMarker,
  }) =>
      (select(assignments)
            ..where((t) =>
                t.studentId.equals(studentId) &
                t.subjectId.equals(subjectId) &
                t.termMarker.equals(termMarker))
            ..orderBy([(t) => OrderingTerm.desc(t.assignedAt)]))
          .get();

  /// Rolling year-long totals for one student+subject, across every term —
  /// the metric the parent (all-subjects) view keeps regardless of which
  /// single term a detail screen is looking at.
  Future<SubjectYearProgress> yearProgress({
    required int studentId,
    required String subjectId,
  }) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS assigned, '
      '       COUNT(completed_at) AS completed, '
      '       COALESCE(SUM(CASE WHEN completed_at IS NOT NULL '
      '                          THEN point_value ELSE 0 END), 0) AS points '
      'FROM assignments WHERE student_id = ? AND subject_id = ?',
      variables: [Variable.withInt(studentId), Variable.withString(subjectId)],
      readsFrom: {assignments},
    ).getSingle();
    return SubjectYearProgress(
      assigned: row.read<int>('assigned'),
      completed: row.read<int>('completed'),
      points: row.read<int>('points'),
    );
  }

  /// Same rollup as [yearProgress], for every subject this student has
  /// assignments in — one grouped query instead of one per subject card.
  Future<Map<String, SubjectYearProgress>> yearProgressBySubject(
      int studentId) async {
    final rows = await customSelect(
      'SELECT subject_id, COUNT(*) AS assigned, '
      '       COUNT(completed_at) AS completed, '
      '       COALESCE(SUM(CASE WHEN completed_at IS NOT NULL '
      '                          THEN point_value ELSE 0 END), 0) AS points '
      'FROM assignments WHERE student_id = ? GROUP BY subject_id',
      variables: [Variable.withInt(studentId)],
      readsFrom: {assignments},
    ).get();
    return {
      for (final r in rows)
        r.read<String>('subject_id'): SubjectYearProgress(
          assigned: r.read<int>('assigned'),
          completed: r.read<int>('completed'),
          points: r.read<int>('points'),
        ),
    };
  }
}
