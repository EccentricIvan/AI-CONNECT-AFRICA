// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_subject_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomSubjectDaoMixin on DatabaseAccessor<OticDatabase> {
  $CustomSubjectsTable get customSubjects => attachedDatabase.customSubjects;
  CustomSubjectDaoManager get managers => CustomSubjectDaoManager(this);
}

class CustomSubjectDaoManager {
  final _$CustomSubjectDaoMixin _db;
  CustomSubjectDaoManager(this._db);
  $$CustomSubjectsTableTableManager get customSubjects =>
      $$CustomSubjectsTableTableManager(
        _db.attachedDatabase,
        _db.customSubjects,
      );
}
