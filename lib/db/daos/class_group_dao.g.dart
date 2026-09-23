// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_group_dao.dart';

// ignore_for_file: type=lint
mixin _$ClassGroupDaoMixin on DatabaseAccessor<OticDatabase> {
  $ClassGroupsTable get classGroups => attachedDatabase.classGroups;
  $StudentsTable get students => attachedDatabase.students;
  $TopicProgressTable get topicProgress => attachedDatabase.topicProgress;
  ClassGroupDaoManager get managers => ClassGroupDaoManager(this);
}

class ClassGroupDaoManager {
  final _$ClassGroupDaoMixin _db;
  ClassGroupDaoManager(this._db);
  $$ClassGroupsTableTableManager get classGroups =>
      $$ClassGroupsTableTableManager(_db.attachedDatabase, _db.classGroups);
  $$StudentsTableTableManager get students =>
      $$StudentsTableTableManager(_db.attachedDatabase, _db.students);
  $$TopicProgressTableTableManager get topicProgress =>
      $$TopicProgressTableTableManager(_db.attachedDatabase, _db.topicProgress);
}
