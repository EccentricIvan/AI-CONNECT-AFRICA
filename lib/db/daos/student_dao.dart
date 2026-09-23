import 'package:drift/drift.dart';
import '../otic_database.dart';
import '../tables/students_table.dart';

part 'student_dao.g.dart';

@DriftAccessor(tables: [Students])
class StudentDao extends DatabaseAccessor<OticDatabase>
    with _$StudentDaoMixin {
  StudentDao(super.db);

  /// Returns the most recently active student, or null if no profile exists
  /// yet. Capped to one row defensively — getSingleOrNull() throws if more
  /// than one row is ever present (e.g. leftover duplicates from a past bug).
  Future<Student?> getActiveStudent() =>
      (select(students)
            ..orderBy([(t) => OrderingTerm.desc(t.lastActiveAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<Student?> getStudentById(int id) =>
      (select(students)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// All profiles on this device — admin view.
  Future<List<Student>> getAllStudents() =>
      (select(students)..orderBy([(t) => OrderingTerm.desc(t.lastActiveAt)]))
          .get();

  /// Every profile, alphabetical, updating live — the learner picker and the
  /// teacher's class lists.
  Stream<List<Student>> watchAllStudents() =>
      (select(students)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<int> createStudent(StudentsCompanion entry) =>
      into(students).insert(entry);

  /// Permanently removes the profile row. The declared cascades on child
  /// tables are not enforced (no `PRAGMA foreign_keys = ON`); callers clear
  /// dependent rows explicitly — see the admin screen.
  Future<void> deleteStudent(int id) =>
      (delete(students)..where((t) => t.id.equals(id))).go();

  Future<void> updateStudent(StudentsCompanion entry) =>
      (update(students)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  /// Bumps lastActiveAt to now.
  Future<void> touchStudent(int id) => updateStudent(
        StudentsCompanion(
          id: Value(id),
          lastActiveAt: Value(DateTime.now()),
        ),
      );

  /// Appends a strength/weakness to the student's cumulative lists.
  Future<void> addInsight(int id, {String? strength, String? weakness}) async {
    final student = await getStudentById(id);
    if (student == null) return;

    List<String> parse(String json) => (json == '[]' || json.isEmpty)
        ? []
        : json
            .replaceAll('[', '')
            .replaceAll(']', '')
            .split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .where((s) => s.isNotEmpty)
            .toList();

    String append(List<String> list, String? item) {
      if (item == null || item.isEmpty) return _toJson(list);
      if (!list.contains(item)) list.add(item);
      if (list.length > 20) list.removeAt(0); // keep last 20
      return _toJson(list);
    }

    final strengths = parse(student.strengthsJson);
    final weaknesses = parse(student.weaknessesJson);

    await updateStudent(StudentsCompanion(
      id: Value(id),
      strengthsJson: Value(append(strengths, strength)),
      weaknessesJson: Value(append(weaknesses, weakness)),
    ));
  }

  String _toJson(List<String> list) =>
      '[${list.map((s) => '"$s"').join(',')}]';
}
