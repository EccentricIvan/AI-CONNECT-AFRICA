import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../ai_core/model/model_locations.dart';
import 'daos/badge_dao.dart';
import 'daos/chat_session_dao.dart';
import 'daos/custom_subject_dao.dart';
import 'daos/path_dao.dart';
import 'daos/project_dao.dart';
import 'daos/session_dao.dart';
import 'daos/student_dao.dart';
import 'daos/topic_resource_dao.dart';
import 'daos/translation_cache_dao.dart';
import 'daos/website_dao.dart';
import 'tables/chat_sessions_table.dart';
import 'tables/custom_subjects_table.dart';
import 'tables/earned_badges_table.dart';
import 'tables/learning_paths_table.dart';
import 'tables/session_summaries_table.dart';
import 'tables/student_projects_table.dart';
import 'tables/students_table.dart';
import 'tables/topic_resources_table.dart';
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
    TopicResources,
    CustomSubjects,
    ChatSessions,
  ],
  daos: [
    StudentDao,
    SessionDao,
    PathDao,
    BadgeDao,
    ProjectDao,
    WebsiteDao,
    TranslationCacheDao,
    TopicResourceDao,
    CustomSubjectDao,
    ChatSessionDao,
  ],
)
class OticDatabase extends _$OticDatabase {
  OticDatabase() : super(_openConnection());

  /// In-memory (or otherwise caller-supplied) database, for tests.
  ///
  /// The default constructor resolves an app storage directory and opens a
  /// file, neither of which exists under `flutter test`. Without this seam a
  /// DAO can only be exercised on a real device, which is how a table can ship
  /// with a query that never matches a row.
  OticDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

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
          if (from < 6) {
            // Teacher-supplied notes/textbook chunks. Purely additive — the
            // hardcoded syllabi in assets/curriculum are untouched, and an
            // upgrade that stops here leaves the app behaving exactly as it
            // did on schema 5.
            await m.createTable(topicResources);
            // createTable does not carry the table's indexes, and a device
            // that upgraded would otherwise run every retrieval as a full
            // scan while a freshly installed one (onCreate → createAll) did
            // not — the same code, quietly slower on exactly the older,
            // weaker hardware this product targets.
            await m.create(idxTopicResourcesLookup);
            await m.create(idxTopicResourcesTitle);
          }
          if (from < 7) {
            // Teacher-created subjects. Also additive: with this table empty
            // the browse grid shows exactly the 16 bundled subjects.
            await m.createTable(customSubjects);
            await m.create(idxCustomSubjectsSubjectId);
          }
          if (from < 8) {
            // One row per chat, indexing the recall files in otic_sessions/.
            // Additive: SessionSummaries still holds the per-turn rows that
            // topic progress and the teacher dashboard read, so an upgrade
            // that stops here loses nothing — the sidebar simply starts
            // empty and refills as new chats are had.
            await m.createTable(chatSessions);
            await m.create(idxChatSessionsRecent);
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
