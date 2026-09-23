import 'package:drift/drift.dart';
import '../otic_database.dart';
import '../tables/app_builder_projects_table.dart';

part 'app_builder_project_dao.g.dart';

@DriftAccessor(tables: [AppBuilderProjects])
class AppBuilderProjectDao extends DatabaseAccessor<OticDatabase>
    with _$AppBuilderProjectDaoMixin {
  AppBuilderProjectDao(super.db);

  Future<List<AppBuilderProject>> getProjectsForStudent(int studentId) =>
      (select(appBuilderProjects)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<AppBuilderProject?> getProjectById(int id) =>
      (select(appBuilderProjects)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> saveProject(AppBuilderProjectsCompanion project) =>
      into(appBuilderProjects).insert(project);

  Future<void> updateProject(int id, AppBuilderProjectsCompanion data) =>
      (update(appBuilderProjects)..where((t) => t.id.equals(id))).write(data);

  Future<void> deleteProject(int id) =>
      (delete(appBuilderProjects)..where((t) => t.id.equals(id))).go();
}
