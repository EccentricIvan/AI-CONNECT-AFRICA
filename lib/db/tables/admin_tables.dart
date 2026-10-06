import 'package:drift/drift.dart';

/// The school's one Admin, on the device where they sign in.
///
/// The Admin keeps the school's records: teachers, classes and streams,
/// subjects, teaching assignments, learners and their enrolments. Only the
/// Admin changes them; every device runs the same app, and the Admin syncs
/// the records from their device to another, one way. Single row (id 1).
@DataClassName('AdminIdentityRow')
class AdminIdentity extends Table {
  @override
  String get tableName => 'admin_identity';

  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// Salted SHA-256 of the Admin's PIN.
  TextColumn get pinSalt => text()();
  TextColumn get pinHash => text()();

  /// ISO-8601 UTC.
  TextColumn get createdAt => text()();

  /// The Admin's Ed25519 signing seed: every bundle of school records the
  /// Admin sends is signed with it. Minted on first send.
  TextColumn get signingSeed => text().nullable()();

  /// Version of the last bundle sent; each send goes one higher.
  IntColumn get recordsVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// On a device that received the Admin's school records: whose they are
/// and which version, so only that Admin's newer records are ever taken.
/// Single row (id 1).
@DataClassName('AdminRecordsStateRow')
class AdminRecordsState extends Table {
  @override
  String get tableName => 'admin_records_state';

  IntColumn get id => integer()();

  /// The Admin key pinned by the first records this device took.
  TextColumn get adminPublicKey => text()();
  IntColumn get version => integer()();
  TextColumn get schoolId => text()();

  /// ISO-8601 UTC.
  TextColumn get receivedAt => text()();

  /// The Admin's details sealed under their passphrase, when sent so the
  /// Admin can take over here; cleared once they do.
  TextColumn get takeoverJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A teacher assigned by the Admin to teach one subject to one
/// class/stream, in an academic year and term. What a teacher may change,
/// share and sync follows from these, never from who created what.
@DataClassName('TeachingAssignment')
@TableIndex(name: 'idx_teaching_assignments_teacher', columns: {#teacherId})
class TeachingAssignments extends Table {
  @override
  String get tableName => 'teaching_assignments';

  IntColumn get id => integer().autoIncrement()();

  /// Portable id, the same on every device the records reach.
  TextColumn get uuid => text().unique()();

  /// `teacher_profiles.id`.
  IntColumn get teacherId => integer()();

  /// `class_groups.group_uuid` — the class/stream.
  TextColumn get classGroupUuid => text()();
  TextColumn get subjectId => text()();
  IntColumn get academicYear => integer()();

  /// 1, 2 or 3; 0 for the whole year.
  IntColumn get term => integer().withDefault(const Constant(0))();

  /// ISO-8601 UTC.
  TextColumn get createdAt => text()();
}

/// A learner enrolled by the Admin in one class/stream for an academic
/// year. `students.class_group_id` mirrors the active one.
@DataClassName('StudentEnrolment')
@TableIndex(name: 'idx_student_enrolments_student', columns: {#studentId})
class StudentEnrolments extends Table {
  @override
  String get tableName => 'student_enrolments';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();

  /// `students.id`.
  IntColumn get studentId => integer()();
  TextColumn get classGroupUuid => text()();
  IntColumn get academicYear => integer()();

  /// 'active' or 'withdrawn'. A withdrawn enrolment is kept, never deleted.
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// ISO-8601 UTC.
  TextColumn get createdAt => text()();
}

/// Which teacher uploaded each of this device's notes, so teachers who
/// share a subject can't change each other's materials. Keyed like
/// `resource_shares`: (subject, document title). Local only, never synced.
@DataClassName('NoteOwner')
class NoteOwners extends Table {
  @override
  String get tableName => 'note_owners';

  TextColumn get subjectId => text()();
  TextColumn get documentTitle => text()();

  /// `teacher_profiles.id`.
  IntColumn get teacherId => integer()();

  @override
  Set<Column> get primaryKey => {subjectId, documentTitle};
}
