// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_resource_dao.dart';

// ignore_for_file: type=lint
mixin _$TopicResourceDaoMixin on DatabaseAccessor<OticDatabase> {
  $TopicResourcesTable get topicResources => attachedDatabase.topicResources;
  TopicResourceDaoManager get managers => TopicResourceDaoManager(this);
}

class TopicResourceDaoManager {
  final _$TopicResourceDaoMixin _db;
  TopicResourceDaoManager(this._db);
  $$TopicResourcesTableTableManager get topicResources =>
      $$TopicResourcesTableTableManager(
        _db.attachedDatabase,
        _db.topicResources,
      );
}
