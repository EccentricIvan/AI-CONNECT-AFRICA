// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_sync_dao.dart';

// ignore_for_file: type=lint
mixin _$ClassSyncDaoMixin on DatabaseAccessor<OticDatabase> {
  $ClassGroupsTable get classGroups => attachedDatabase.classGroups;
  $ResourceSharesTable get resourceShares => attachedDatabase.resourceShares;
  $SyncIdentityTable get syncIdentity => attachedDatabase.syncIdentity;
  $TopicResourcesTable get topicResources => attachedDatabase.topicResources;
  $SyncStateTable get syncState => attachedDatabase.syncState;
  $ServedChannelsTable get servedChannels => attachedDatabase.servedChannels;
  $MemberReportsTable get memberReports => attachedDatabase.memberReports;
  ClassSyncDaoManager get managers => ClassSyncDaoManager(this);
}

class ClassSyncDaoManager {
  final _$ClassSyncDaoMixin _db;
  ClassSyncDaoManager(this._db);
  $$ClassGroupsTableTableManager get classGroups =>
      $$ClassGroupsTableTableManager(_db.attachedDatabase, _db.classGroups);
  $$ResourceSharesTableTableManager get resourceShares =>
      $$ResourceSharesTableTableManager(
        _db.attachedDatabase,
        _db.resourceShares,
      );
  $$SyncIdentityTableTableManager get syncIdentity =>
      $$SyncIdentityTableTableManager(_db.attachedDatabase, _db.syncIdentity);
  $$TopicResourcesTableTableManager get topicResources =>
      $$TopicResourcesTableTableManager(
        _db.attachedDatabase,
        _db.topicResources,
      );
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db.attachedDatabase, _db.syncState);
  $$ServedChannelsTableTableManager get servedChannels =>
      $$ServedChannelsTableTableManager(
        _db.attachedDatabase,
        _db.servedChannels,
      );
  $$MemberReportsTableTableManager get memberReports =>
      $$MemberReportsTableTableManager(_db.attachedDatabase, _db.memberReports);
}
