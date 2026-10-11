import 'package:drift/drift.dart';

import '../otic_database.dart';
import '../tables/custom_subjects_table.dart';

part 'custom_subject_dao.g.dart';

/// Read/write access to teacher-created subjects.
///
/// Additive only: nothing here can read or alter the bundled curriculum.
@DriftAccessor(tables: [CustomSubjects])
class CustomSubjectDao extends DatabaseAccessor<OticDatabase>
    with _$CustomSubjectDaoMixin {
  CustomSubjectDao(super.db);

  Future<List<CustomSubject>> all() {
    return (select(customSubjects)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<CustomSubject?> bySubjectId(String subjectId) {
    return (select(customSubjects)
          ..where((t) => t.subjectId.equals(subjectId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> insertSubject({
    required String subjectId,
    required String name,
    required String icon,
    required String color,
    DateTime? createdAt,
    int? ownerTeacherId,
  }) {
    return into(customSubjects).insert(
      CustomSubjectsCompanion.insert(
        subjectId: subjectId,
        name: name,
        icon: Value(icon),
        color: Value(color),
        createdAt: (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        ownerTeacherId: Value(ownerTeacherId),
      ),
    );
  }

  /// Renames a subject; [style] restyles its card to match the new name.
  Future<void> rename(
    String subjectId,
    String name, {
    ({String icon, String color})? style,
  }) async {
    await (update(customSubjects)..where((t) => t.subjectId.equals(subjectId)))
        .write(
          CustomSubjectsCompanion(
            name: Value(name),
            icon: style == null ? const Value.absent() : Value(style.icon),
            color: style == null ? const Value.absent() : Value(style.color),
          ),
        );
  }

  /// Removes the subject row only. The caller is responsible for its
  /// resources — see [CustomSubjectService.delete], which removes both in one
  /// transaction so a subject can never vanish while its material lingers.
  Future<int> deleteSubject(String subjectId) {
    return (delete(customSubjects)..where((t) => t.subjectId.equals(subjectId)))
        .go();
  }

  Future<bool> exists(String subjectId) async {
    return await bySubjectId(subjectId) != null;
  }
}
