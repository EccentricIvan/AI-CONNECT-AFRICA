// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_session_dao.dart';

// ignore_for_file: type=lint
mixin _$ChatSessionDaoMixin on DatabaseAccessor<OticDatabase> {
  $ChatSessionsTable get chatSessions => attachedDatabase.chatSessions;
  ChatSessionDaoManager get managers => ChatSessionDaoManager(this);
}

class ChatSessionDaoManager {
  final _$ChatSessionDaoMixin _db;
  ChatSessionDaoManager(this._db);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db.attachedDatabase, _db.chatSessions);
}
