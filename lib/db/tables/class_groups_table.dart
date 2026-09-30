import 'package:drift/drift.dart';

/// A class, optionally split into a stream — e.g. "S2" / "East".
///
/// A stream is a parallel section of one class, so it is modelled as an
/// optional label on the class row rather than a second table: "S2 East" and
/// "S2 West" are two rows. A learner belongs to at most one row at a time, via
/// `students.class_group_id`.
///
/// [groupUuid]'s uniqueness is enforced by [idxClassGroupsGroupUuid], not a
/// `UNIQUE` column constraint — SQLite's `ALTER TABLE ADD COLUMN` rejects a
/// `UNIQUE` column outright (`Cannot add a UNIQUE column`), which broke the
/// very first real upgrade past schema 11: `onCreate` never exercises that
/// path, so nothing caught it before a device with an existing database hit
/// it. A separate unique index has no such restriction and can be created
/// once the column exists and is backfilled — see the schema-11 migration.
@TableIndex(
  name: 'idx_class_groups_group_uuid',
  columns: {#groupUuid},
  unique: true,
)
class ClassGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get className => text()();

  /// Null when the class has no streams.
  TextColumn get streamName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Portable identity for this class/stream, independent of [id].
  ///
  /// [id] is a local autoincrement — a teacher's device and a student's
  /// device each mint their own, so two unrelated rows can share the same
  /// int. Scoped sync (`lib/collaboration/sync/`) addresses a class/stream
  /// across devices by this UUID instead, minted once at [createClass] and
  /// never reused. Nullable only so a fresh column can exist before a
  /// backfill runs; every row written from here on gets one.
  TextColumn get groupUuid => text().nullable()();

  // ── Class sync (lib/collaboration/sync/) ───────────────────────────────

  /// School this class belongs to ([SyncIdentity.schoolId]). A student
  /// device refuses to join a class from a different school than its own.
  TextColumn get schoolId => text().nullable()();

  /// The class/stream's shared secret. Minted on the teacher's device the
  /// first time the class is synced, copied to a student device at join.
  /// Only holders can ask for, or read, the class's notes.
  TextColumn get classKey => text().nullable()();

  /// On a joined class: the teacher device's Ed25519 public key, pinned at
  /// join. Replies not signed by it are rejected.
  TextColumn get teacherPublicKey => text().nullable()();

  /// True on a student device for a class it joined from a teacher; false
  /// for a class this device created. Only created classes are ever served.
  BoolColumn get joined => boolean().withDefault(const Constant(false))();

  // ── Co-teachers (lib/db/tables/co_teachers_table.dart) ─────────────────

  /// The newest root-signed `ClassRoster` version this device has verified
  /// for this class. Null/absent means no co-teacher has ever existed for
  /// it, which behaves identically to before this existed — every subject
  /// resolves to [teacherPublicKey].
  IntColumn get rosterVersion => integer().nullable()();

  /// The cached roster itself (JSON), re-verified against [teacherPublicKey]
  /// whenever it's used, never trusted on its own.
  TextColumn get rosterJson => text().nullable()();
}
