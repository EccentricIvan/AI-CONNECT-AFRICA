import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/daos/assignment_dao.dart';
import '../db/otic_database.dart';

export '../db/daos/assignment_dao.dart' show SubjectYearProgress;

/// Coordinates `assignments` against the student's master profile
/// (`students.total_points`) so the two can never drift apart.
///
/// Everything that moves points goes through [markCompleted] — nothing else
/// in this repository writes `total_points`, and [AssignmentDao] itself
/// never touches [Students] at all. That single choke point is what makes
/// "assigned/completed ⇒ points" a property of this class instead of
/// something every caller has to remember to keep in sync by hand.
class AcademicScoreTrackerRepository {
  AcademicScoreTrackerRepository(this._db);

  final OticDatabase _db;

  AssignmentDao get _assignments => _db.assignmentDao;

  Future<int> assign({
    required int studentId,
    required String subjectId,
    required int termMarker,
    required String title,
    int pointValue = 10,
  }) =>
      _assignments.assign(
        studentId: studentId,
        subjectId: subjectId,
        termMarker: termMarker,
        title: title,
        pointValue: pointValue,
      );

  /// Marks [assignmentId] done and credits its points to the student's
  /// profile — one Drift transaction, so a process death between the two
  /// writes cannot leave the assignment marked done with no points awarded,
  /// or points awarded against work still shown outstanding.
  ///
  /// Idempotent: completing an already-completed assignment is a no-op
  /// rather than a second award, so a retried request (a flaky UI tap, a
  /// resumed sync) can never double-count.
  Future<void> markCompleted(int assignmentId, {DateTime? completedAt}) async {
    try {
      await _db.transaction(() async {
        final assignment = await _assignments.byId(assignmentId);
        if (assignment == null) {
          throw StateError('assignment $assignmentId not found');
        }
        if (assignment.completedAt != null) return;

        final when = completedAt ?? DateTime.now();
        await _assignments.setCompleted(assignmentId, when);

        final student =
            await _db.studentDao.getStudentById(assignment.studentId);
        if (student == null) {
          throw StateError('student ${assignment.studentId} not found — '
              'rolling back the completion too');
        }
        await _db.studentDao.updateStudent(
          StudentsCompanion(
            id: Value(student.id),
            totalPoints: Value(student.totalPoints + assignment.pointValue),
          ),
        );
      });
    } catch (e, st) {
      // A constraint collision or a vanished row rolls the whole
      // transaction back automatically (drift wraps this in SQLite's own
      // transaction) — nothing here is half-applied. Surfaced to the
      // caller as a normal exception; logged here so a silent catch
      // upstream still leaves a trace of what actually failed.
      debugPrint('AcademicScoreTrackerRepository.markCompleted($assignmentId) '
          'failed: $e\n$st');
      rethrow;
    }
  }

  Future<List<Assignment>> forTerm({
    required int studentId,
    required String subjectId,
    required int termMarker,
  }) =>
      _assignments.forTerm(
        studentId: studentId,
        subjectId: subjectId,
        termMarker: termMarker,
      );

  /// Rolling, year-long progress for one subject — every term combined,
  /// regardless of which term's assignments a caller has been looking at.
  Future<SubjectYearProgress> yearProgress({
    required int studentId,
    required String subjectId,
  }) =>
      _assignments.yearProgress(studentId: studentId, subjectId: subjectId);

  Future<Map<String, SubjectYearProgress>> yearProgressBySubject(
          int studentId) =>
      _assignments.yearProgressBySubject(studentId);
}
