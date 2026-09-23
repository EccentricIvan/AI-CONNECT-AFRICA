// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_builder_project_dao.dart';

// ignore_for_file: type=lint
mixin _$AppBuilderProjectDaoMixin on DatabaseAccessor<OticDatabase> {
  $AppBuilderProjectsTable get appBuilderProjects =>
      attachedDatabase.appBuilderProjects;
  AppBuilderProjectDaoManager get managers => AppBuilderProjectDaoManager(this);
}

class AppBuilderProjectDaoManager {
  final _$AppBuilderProjectDaoMixin _db;
  AppBuilderProjectDaoManager(this._db);
  $$AppBuilderProjectsTableTableManager get appBuilderProjects =>
      $$AppBuilderProjectsTableTableManager(
        _db.attachedDatabase,
        _db.appBuilderProjects,
      );
}
