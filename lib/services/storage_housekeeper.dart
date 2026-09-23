import 'package:flutter/foundation.dart';

import '../db/otic_database.dart';
import '../memory/session_recall_store.dart';

/// Rolling retention window for reopenable chat history — see the
/// class doc on why this is `chat_sessions`/recall files specifically, not
/// `topic_progress`, `SessionSummaries`, or anything badges/mastery reads.
///
/// A student can exempt one chat from this with "Keep this chat"
/// (`ChatSessions.pinned`, toggled from the Recent chats sidebar) — this
/// sweep never deletes a pinned row, however old.
const kChatHistoryRetention = Duration(days: 30);

/// What one [StorageHousekeeper.runSweep] actually did.
class HousekeepingReport {
  const HousekeepingReport({
    required this.expiredSessions,
    required this.orphanedFiles,
    this.error,
  });

  /// Chats older than [kChatHistoryRetention] whose row (and recall file)
  /// were deleted this sweep.
  final int expiredSessions;

  /// Recall files deleted that had no `chat_sessions` row at all — already
  /// orphaned before this sweep touched retention.
  final int orphanedFiles;

  int get removed => expiredSessions + orphanedFiles;

  /// Set on failure — the counts above are whatever completed before the
  /// error, not necessarily 0 (a sweep that fails partway through still
  /// keeps what it already cleaned up; nothing here is transactional,
  /// because there is nothing to roll back to — a deleted file staying
  /// deleted is always correct, expired or orphaned either way).
  final String? error;

  bool get ok => error == null;
}

/// Sweeps this device's own sandboxed storage: ages out chat history past
/// [kChatHistoryRetention], then removes any recall file no `chat_sessions`
/// row (post-retention) still points at.
///
/// Scope, deliberately: `chat_sessions` rows and their recall files
/// (`<app storage>/otic_sessions/*.json`) — the reopenable "Recent chats"
/// feature specifically. Retention stops there on purpose:
///  * `SessionSummaries` (per-turn rows) is untouched — the teacher
///    dashboard and topic-progress rollups are built on it, and CLAUDE.md
///    is explicit that it is a separate table from `chat_sessions` for
///    exactly this reason. Aging out a reopenable chat must never look like
///    a student stopped learning that topic.
///  * `topic_progress`, badges and `students.total_points` are permanent
///    progress, not history — nothing here ever deletes them.
///  * Every other on-disk asset is either kept outside app storage by
///    design (an exported site/app/certificate goes through the platform's
///    own save dialog — not this app's to manage), or never written to a
///    file at all (teacher notes are parsed straight to `topic_resources`
///    rows, the original discarded on the spot; model GGUFs are managed by
///    [ModelManager], not this).
///
/// [SessionRecallStore.pruneExcept] already does the actual file-vs-row
/// comparison and deletion (an async, non-blocking directory stream); this
/// class adds the two things that were missing — a rolling age-out at the
/// database level, and something that actually calls either of them.
class StorageHousekeeper {
  StorageHousekeeper(this._db, {SessionRecallStore? store})
      : _store = store ?? SessionRecallStore();

  final OticDatabase _db;
  final SessionRecallStore _store;

  bool _running = false;

  /// True while a sweep is in flight — callers use this to skip a second,
  /// overlapping trigger (e.g. a resume firing while startup's own sweep
  /// hasn't finished) rather than queuing redundant work.
  bool get isRunning => _running;

  Future<HousekeepingReport> runSweep() async {
    if (_running) {
      return const HousekeepingReport(expiredSessions: 0, orphanedFiles: 0);
    }
    _running = true;
    try {
      // 1) Roll off chat history past the retention window. This only
      // removes the `chat_sessions` index rows — the matching recall files
      // are swept in step 2, which runs against the id set *after* this
      // delete, so an aged-out chat's file is removed there as an ordinary
      // orphan rather than needing its own delete loop here.
      final cutoff = DateTime.now().subtract(kChatHistoryRetention);
      final expired = await _db.chatSessionDao.deleteOlderThan(cutoff);

      // 2) Everything still on disk that no surviving row points at —
      // orphans from a deleted student, an interrupted write, or the
      // FK-cascade-is-decorative situation CLAUDE.md documents, now
      // including the ones step 1 just aged out.
      //
      // One query, not a micro-batched scan: on the scale this app ever
      // reaches (a shared classroom device's own session history — tens to
      // low thousands of rows, never millions), the whole id set is a few
      // hundred KB in memory at most, and every id is looked up at most
      // once per file while the directory streams. Batching *this* read
      // would only add round trips for a table this small; the part that
      // actually must not block is the file sweep, which already streams.
      final keepIds = await _db.chatSessionDao.allSessionIds();
      final removedFiles = await _store.pruneExcept(keepIds);

      return HousekeepingReport(
        expiredSessions: expired.length,
        // pruneExcept's count includes the files step 1 just aged out —
        // subtract those back out so the two report fields don't double
        // count the same file under two different reasons.
        orphanedFiles: (removedFiles - expired.length).clamp(0, removedFiles),
      );
    } catch (e, st) {
      debugPrint('StorageHousekeeper.runSweep failed: $e\n$st');
      return HousekeepingReport(
        expiredSessions: 0,
        orphanedFiles: 0,
        error: '$e',
      );
    } finally {
      _running = false;
    }
  }
}
