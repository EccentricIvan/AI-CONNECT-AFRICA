import 'package:drift/drift.dart';
import '../otic_database.dart';
import '../tables/chat_sessions_table.dart';

part 'chat_session_dao.g.dart';

@DriftAccessor(tables: [ChatSessions])
class ChatSessionDao extends DatabaseAccessor<OticDatabase>
    with _$ChatSessionDaoMixin {
  ChatSessionDao(super.db);

  /// Insert or update the index row for one chat.
  ///
  /// Keyed on the session id, so a second turn in the same chat *updates* the
  /// existing row. That is the whole difference from `SessionDao.saveSession`,
  /// which inserts a fresh row per turn and is why the sidebar used to show
  /// the same conversation a dozen times over.
  Future<void> upsertSession({
    required String id,
    required int studentId,
    required String title,
    required String topic,
    required String preview,
    required String stage,
    required int turnCount,
    DateTime? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now();
    await into(chatSessions).insert(
      ChatSessionsCompanion.insert(
        id: id,
        studentId: studentId,
        title: title,
        topic: Value(topic),
        preview: Value(preview),
        stage: Value(stage),
        turnCount: Value(turnCount),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
      // createdAt is deliberately left out of the update set: a chat keeps the
      // time it started, while updatedAt moves with each turn so the sidebar
      // orders by most recent activity.
      onConflict: DoUpdate(
        (_) => ChatSessionsCompanion(
          title: Value(title),
          topic: Value(topic),
          preview: Value(preview),
          stage: Value(stage),
          turnCount: Value(turnCount),
          updatedAt: Value(now),
        ),
        target: [chatSessions.id],
      ),
    );
  }

  Future<List<ChatSession>> recentSessions(int studentId, {int limit = 30}) =>
      (select(chatSessions)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .get();

  /// Live list for the sidebar — updates as soon as a turn is saved, without
  /// the caller having to invalidate anything.
  Stream<List<ChatSession>> watchRecentSessions(int studentId,
          {int limit = 30}) =>
      (select(chatSessions)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .watch();

  Future<ChatSession?> findSession(String id) =>
      (select(chatSessions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> deleteSession(String id) async {
    await (delete(chatSessions)..where((t) => t.id.equals(id))).go();
  }

  /// Remove every chat belonging to a student, returning their ids so the
  /// caller can delete the matching recall files.
  ///
  /// The `onDelete: cascade` on this table is decorative: nothing in the app
  /// issues `PRAGMA foreign_keys = ON`, so SQLite never enforces it and rows
  /// would simply orphan when an admin removes a student. That is true of
  /// every child table here and is not something to change quietly from this
  /// feature, so this path cleans up explicitly instead.
  Future<Set<String>> deleteForStudent(int studentId) async {
    final rows = await (select(chatSessions)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    await (delete(chatSessions)..where((t) => t.studentId.equals(studentId)))
        .go();
    return {for (final r in rows) r.id};
  }

  Future<void> renameSession(String id, String title) async {
    await (update(chatSessions)..where((t) => t.id.equals(id)))
        .write(ChatSessionsCompanion(title: Value(title)));
  }

  /// Every id this student still has, for pruning orphaned recall files.
  Future<Set<String>> allSessionIds() async {
    final rows = await select(chatSessions).get();
    return {for (final r in rows) r.id};
  }

  /// Removes every chat whose last activity is before [cutoff] — every
  /// student, not one, and never a pinned one — and returns their ids so
  /// the caller can also delete the matching recall files. Used by
  /// [StorageHousekeeper]'s rolling retention sweep.
  ///
  /// `updated_at`, not `created_at`: a chat a student keeps coming back to
  /// stays, even if it started months ago — only one that has genuinely gone
  /// quiet for the whole window ages out.
  Future<Set<String>> deleteOlderThan(DateTime cutoff) async {
    final rows = await (select(chatSessions)
          ..where((t) =>
              t.updatedAt.isSmallerThanValue(cutoff) &
              t.pinned.equals(false)))
        .get();
    if (rows.isEmpty) return const {};
    await (delete(chatSessions)
          ..where((t) =>
              t.updatedAt.isSmallerThanValue(cutoff) &
              t.pinned.equals(false)))
        .go();
    return {for (final r in rows) r.id};
  }

  /// "Keep this chat" toggle — see `ChatSessions.pinned`.
  Future<void> setPinned(String id, bool pinned) =>
      (update(chatSessions)..where((t) => t.id.equals(id)))
          .write(ChatSessionsCompanion(pinned: Value(pinned)));
}
