import 'package:drift/drift.dart';

/// Subjects a teacher created on the device, alongside the bundled ones.
///
/// The 16 hardcoded subjects in `CurriculumService._subjects`, backed by
/// `assets/curriculum/*.json`, are untouched and remain the permanent
/// structural base. A row here is purely additional: it adds a subject to the
/// browse grid, and its teaching content is whatever the teacher uploaded into
/// `topic_resources` under the same [subjectId].
///
/// Deleting every row in this table returns the app to exactly the 16 bundled
/// subjects.
@TableIndex(name: 'idx_custom_subjects_subject_id', columns: {#subjectId})
class CustomSubjects extends Table {
  @override
  String get tableName => 'custom_subjects';

  IntColumn get id => integer().autoIncrement()();

  /// Slug used in routes and as `topic_resources.subject_id`.
  ///
  /// Unique, and validated against the bundled ids before insert so a teacher
  /// cannot create a second "chemistry" that shadows the bundled one — see
  /// [CustomSubjectService.create].
  TextColumn get subjectId => text().unique()();

  /// What the teacher typed, shown on the subject card.
  TextColumn get name => text()();

  /// Icon key and card colour, using the same vocabulary as the bundled
  /// curriculum JSON so one card widget renders both kinds.
  TextColumn get icon => text().withDefault(const Constant('menu_book'))();
  TextColumn get color => text().withDefault(const Constant('#4F46E5'))();

  /// ISO-8601 UTC, matching `topic_resources.created_at`.
  TextColumn get createdAt => text()();
}
