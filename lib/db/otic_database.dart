import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../ai_core/model/model_locations.dart';
import 'daos/badge_dao.dart';
import 'daos/path_dao.dart';
import 'daos/project_dao.dart';
import 'daos/session_dao.dart';
import 'daos/student_dao.dart';
import 'daos/translation_cache_dao.dart';
import 'daos/website_dao.dart';
import 'tables/earned_badges_table.dart';
import 'tables/learning_paths_table.dart';
import 'tables/session_summaries_table.dart';
import 'tables/student_projects_table.dart';
import 'tables/students_table.dart';
import 'tables/translation_cache_table.dart';
import 'tables/topic_progress_table.dart';
import 'tables/website_projects_table.dart';

part 'otic_database.g.dart';

@DriftDatabase(
  tables: [
    Students,
    SessionSummaries,
    TopicProgress,
    LearningPaths,
    EarnedBadges,
    StudentProjects,
    WebsiteProjects,
    TranslationCacheEntries,
  ],
  daos: [
    StudentDao,
    SessionDao,
    PathDao,
    BadgeDao,
    ProjectDao,
    WebsiteDao,
    TranslationCacheDao,
  ],
)
class OticDatabase extends _$OticDatabase {
  OticDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(learningPaths);
          }
          if (from < 3) {
            await m.addColumn(students, students.streakDays);
            await m.addColumn(students, students.lastStreakDate);
            await m.addColumn(students, students.totalPoints);
            await m.createTable(earnedBadges);
            await m.createTable(studentProjects);
          }
          if (from < 4) {
            await m.createTable(websiteProjects);
          }
          if (from < 5) {
            await m.createTable(translationCacheEntries);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await resolveAppStorageDirectory();
      final file = File(p.join(dir.path, 'otic_student_db.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
