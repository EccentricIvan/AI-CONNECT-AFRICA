// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assignment_dao.dart';

// ignore_for_file: type=lint
mixin _$AssignmentDaoMixin on DatabaseAccessor<OticDatabase> {
  $AssignmentsTable get assignments => attachedDatabase.assignments;
  AssignmentDaoManager get managers => AssignmentDaoManager(this);
}

class AssignmentDaoManager {
  final _$AssignmentDaoMixin _db;
  AssignmentDaoManager(this._db);
  $$AssignmentsTableTableManager get assignments =>
      $$AssignmentsTableTableManager(_db.attachedDatabase, _db.assignments);
}
