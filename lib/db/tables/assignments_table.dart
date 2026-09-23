import 'package:drift/drift.dart';
import 'students_table.dart';
import 'topic_resources_table.dart' show kAllTermsMarker;

/// One graded piece of work a student is (or was) assigned, scoped to a
/// subject and a school term.
///
/// Deliberately separate from `topic_progress` (per-topic mastery, updated
/// as the tutor teaches) — an assignment is a discrete, teacher-defined unit
/// of work with a completion event and a point value, not a rolling mastery
/// score. [AcademicScoreTrackerRepository] is what ties a completion to the
/// student's points.
@TableIndex(
  name: 'idx_assignments_student_subject_term',
  columns: {#studentId, #subjectId, #termMarker},
)
class Assignments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();

  /// Same slug space as `topic_resources.subject_id` / `custom_subjects`.
  TextColumn get subjectId => text()();

  /// 1, 2 or 3 — unlike `topic_resources.term_marker`, an assignment always
  /// belongs to exactly one term; there is no "all terms" assignment.
  IntColumn get termMarker => integer()();

  TextColumn get title => text()();
  IntColumn get pointValue => integer().withDefault(const Constant(10))();

  TextColumn get assignedAt => text()();

  /// Null while outstanding. Set once, by
  /// [AcademicScoreTrackerRepository.markCompleted] — that is the one place
  /// point totals move, so a completion can never happen twice and double
  /// count.
  TextColumn get completedAt => text().nullable()();
}

/// Real (non-"all terms") term markers an assignment can carry.
const kAssignmentTermMarkers = [1, 2, 3];

// Re-exported so callers of this table don't also need
// topic_resources_table.dart just to reject [kAllTermsMarker].
const kNotATermMarker = kAllTermsMarker;
