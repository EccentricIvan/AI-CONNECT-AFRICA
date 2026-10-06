import 'package:drift/drift.dart';

/// A co-teacher device's own record of classes it has been delegated a
/// subject in.
///
/// Deliberately not a row in `ClassGroups`: every `ownedClasses`/
/// `joinedByUuid`/`joined` call site treats that table as either "a class
/// this device fully owns" or "a class this device joined as a student" —
/// a delegated class is neither, and a separate table means none of those
/// call sites need to change to avoid misclassifying one.
@DataClassName('CoTeachingClass')
@TableIndex(
  name: 'idx_co_teaching_classes_uuid',
  columns: {#classGroupUuid},
  unique: true,
)
class CoTeachingClasses extends Table {
  @override
  String get tableName => 'co_teaching_classes';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get classGroupUuid => text()();
  TextColumn get className => text()();
  TextColumn get streamName => text().nullable()();
  TextColumn get schoolId => text()();

  /// The class's shared secret, same as `ClassGroups.classKey` on the root's
  /// own row — handed over in the co-teacher invite bundle.
  TextColumn get classKey => text()();

  /// The root teacher device's Ed25519 public key. Plays the role
  /// `ClassGroups.teacherPublicKey` plays for a student, named distinctly
  /// since this device also has its own `signingSeed` it signs its own
  /// manifests with.
  TextColumn get rootPublicKey => text()();

  /// This device's most recently confirmed allocation (JSON array of subject
  /// ids), refreshed whenever it syncs with root.
  TextColumn get subjectIdsJson => text()();

  /// The newest root-signed roster this device has verified for the class,
  /// cached so it can forward it to a student reaching this device first.
  IntColumn get rosterVersion => integer()();
  TextColumn get rosterJson => text()();

  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  /// The teacher profile that joined as co-teacher; only they share into
  /// it. Local only, never synced.
  IntColumn get ownerTeacherId => integer().nullable()();
}
