import 'package:drift/drift.dart';

import 'class_groups_table.dart';

/// One row = one student profile on this device.
class Students extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get age => integer().nullable()();
  TextColumn get grade => text().nullable()();
  // BCP-47 language code, e.g. 'en', 'sw', 'fr'
  TextColumn get language => text().withDefault(const Constant('en'))();
  // JSON array of interest strings e.g. ["physics","coding"]
  TextColumn get interestsJson => text().withDefault(const Constant('[]'))();
  // 'visual' | 'reading' | 'practice' | 'unknown'
  TextColumn get learningStyle =>
      text().withDefault(const Constant('unknown'))();
  // Cumulative strengths / weaknesses as JSON arrays (updated after sessions)
  TextColumn get strengthsJson => text().withDefault(const Constant('[]'))();
  TextColumn get weaknessesJson => text().withDefault(const Constant('[]'))();
  TextColumn get goalsJson => text().withDefault(const Constant('[]'))();
  // Gamification
  IntColumn get streakDays => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastStreakDate => dateTime().nullable()();
  IntColumn get totalPoints => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastActiveAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// The class/stream this learner is enrolled in, or null when unassigned.
  ///
  /// The declared FK is not enforced (nothing issues `PRAGMA foreign_keys`),
  /// so deleting a class clears this explicitly — see `ClassGroupDao`.
  IntColumn get classGroupId =>
      integer().nullable().references(ClassGroups, #id)();
}
