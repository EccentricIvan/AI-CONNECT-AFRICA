import 'package:drift/drift.dart';
import '../otic_database.dart';
import '../tables/sync_state_table.dart';

part 'sync_state_dao.g.dart';

@DriftAccessor(tables: [SyncState])
class SyncStateDao extends DatabaseAccessor<OticDatabase>
    with _$SyncStateDaoMixin {
  SyncStateDao(super.db);

  Future<SyncStateData?> get(
          {required String classGroupUuid, required String subjectId}) =>
      (select(syncState)
            ..where((t) =>
                t.classGroupUuid.equals(classGroupUuid) &
                t.subjectId.equals(subjectId)))
          .getSingleOrNull();

  /// Records a completed pull, and adds this run's rejections to the
  /// channel's running total rather than overwriting it — a rejection count
  /// that resets every sync would hide a source that is *always* sending one
  /// bad chunk.
  ///
  /// [syncedAtIso] is the server's reported channel version (the same
  /// opaque, lexicographically-sortable ISO string every layer here passes
  /// around as `since`/`version`) — not wall-clock time, so a student
  /// device's clock being wrong can never make a channel look synced past
  /// data it has not actually pulled.
  Future<void> recordSync({
    required String classGroupUuid,
    required String subjectId,
    required String syncedAtIso,
    int rejectedThisRun = 0,
  }) async {
    final existing = await get(
      classGroupUuid: classGroupUuid,
      subjectId: subjectId,
    );
    if (existing == null) {
      await into(syncState).insert(
        SyncStateCompanion.insert(
          classGroupUuid: classGroupUuid,
          subjectId: subjectId,
          lastSyncedAt: syncedAtIso,
          rejectedCount: Value(rejectedThisRun),
        ),
      );
    } else {
      await (update(syncState)..where((t) => t.id.equals(existing.id))).write(
        SyncStateCompanion(
          lastSyncedAt: Value(syncedAtIso),
          rejectedCount: Value(existing.rejectedCount + rejectedThisRun),
        ),
      );
    }
  }
}
