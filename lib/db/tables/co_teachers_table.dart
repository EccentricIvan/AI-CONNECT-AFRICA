import 'package:drift/drift.dart';

/// Root teacher device only: who else is trusted to serve which subjects of
/// one of this device's classes. One row per (class, co-teacher public key).
///
/// The signed, versioned form of this table that travels to students and
/// co-teachers is a `ClassRoster` (`lib/collaboration/sync/class_crypto.dart`)
/// — this table is root's own source of truth it's built from.
@TableIndex(
  name: 'idx_class_co_teachers_unique',
  columns: {#classGroupUuid, #publicKey},
  unique: true,
)
class ClassCoTeachers extends Table {
  @override
  String get tableName => 'class_co_teachers';

  IntColumn get id => integer().autoIncrement()();

  /// [ClassGroups.groupUuid] this allocation is scoped to.
  TextColumn get classGroupUuid => text()();

  /// The co-teacher device's Ed25519 public key, pinned at invite accept and
  /// never re-derived. Its replies for the allocated subjects must be signed
  /// with the matching private key.
  TextColumn get publicKey => text()();

  /// Name the co-teacher typed accepting the invite — shown on "Teachers on
  /// this class".
  TextColumn get name => text()();

  /// JSON array of subject ids allocated to this co-teacher in this class.
  /// Disjoint from every other co-teacher's list for the same class —
  /// enforced at invite time by `CoTeacherDao.addCoTeacher`, since a subject
  /// served by two signers would race their independent version counters.
  TextColumn get subjectIdsJson => text()();

  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}
