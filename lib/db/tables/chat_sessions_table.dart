import 'package:drift/drift.dart';
import 'students_table.dart';

/// Lightweight index over the per-session recall files.
///
/// One row per *chat*, not per turn — `SessionSummaries` keeps the per-turn
/// rows that topic progress and the teacher dashboard are built on, and is
/// untouched. This table exists so the sidebar can list recent chats with a
/// single indexed query and without opening any file.
///
/// The conversation content itself is never stored here; the row only carries
/// what a tile needs to render. The body lives in `SessionRecallStore`.
@TableIndex(name: 'idx_chat_sessions_recent', columns: {#studentId, #updatedAt})
class ChatSessions extends Table {
  /// Matches the recall filename (`<id>.json`).
  TextColumn get id => text().withLength(min: 1, max: 64)();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();

  /// The student's own opening words, clipped — never a model-generated label.
  TextColumn get title => text()();

  /// Coarse detected subject bucket, kept for filtering and grouping.
  TextColumn get topic => text().withDefault(const Constant(''))();

  /// Last tutor line, clipped, for the sidebar's secondary line.
  TextColumn get preview => text().withDefault(const Constant(''))();

  /// Pipeline stage this chat had reached, so reopening resumes it.
  TextColumn get stage => text().withDefault(const Constant('answer'))();

  /// Number of exchanges retained in the recall file.
  IntColumn get turnCount => integer().withDefault(const Constant(0))();

  /// "Keep this chat" — exempts this row from
  /// `ChatSessionDao.deleteOlderThan`'s rolling retention sweep
  /// ([StorageHousekeeper]). Everything else about a pinned chat is
  /// unchanged: it still ages off the top of "Recent chats" once 30 other
  /// chats are more recent (that list is a recency window, not an
  /// archive) — pinning only stops the *deletion*, not the sort order.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
