// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'co_teacher_dao.dart';

// ignore_for_file: type=lint
mixin _$CoTeacherDaoMixin on DatabaseAccessor<OticDatabase> {
  $ClassCoTeachersTable get classCoTeachers => attachedDatabase.classCoTeachers;
  $CoTeachingClassesTable get coTeachingClasses =>
      attachedDatabase.coTeachingClasses;
  $ClassGroupsTable get classGroups => attachedDatabase.classGroups;
  $SyncIdentityTable get syncIdentity => attachedDatabase.syncIdentity;
  CoTeacherDaoManager get managers => CoTeacherDaoManager(this);
}

class CoTeacherDaoManager {
  final _$CoTeacherDaoMixin _db;
  CoTeacherDaoManager(this._db);
  $$ClassCoTeachersTableTableManager get classCoTeachers =>
      $$ClassCoTeachersTableTableManager(
        _db.attachedDatabase,
        _db.classCoTeachers,
      );
  $$CoTeachingClassesTableTableManager get coTeachingClasses =>
      $$CoTeachingClassesTableTableManager(
        _db.attachedDatabase,
        _db.coTeachingClasses,
      );
  $$ClassGroupsTableTableManager get classGroups =>
      $$ClassGroupsTableTableManager(_db.attachedDatabase, _db.classGroups);
  $$SyncIdentityTableTableManager get syncIdentity =>
      $$SyncIdentityTableTableManager(_db.attachedDatabase, _db.syncIdentity);
}
