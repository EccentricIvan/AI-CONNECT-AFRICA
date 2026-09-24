import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../ai_core/model/model_locations.dart';
import 'daos/app_builder_project_dao.dart';
import 'daos/assignment_dao.dart';
import 'daos/badge_dao.dart';
import 'daos/chat_session_dao.dart';
import 'daos/class_group_dao.dart';
import 'daos/custom_subject_dao.dart';
import 'daos/path_dao.dart';
import 'daos/project_dao.dart';
import 'daos/session_dao.dart';
import 'daos/student_dao.dart';
import 'daos/sync_state_dao.dart';
import 'daos/topic_resource_dao.dart';
import 'daos/translation_cache_dao.dart';
import 'daos/website_dao.dart';
import 'tables/app_builder_projects_table.dart';
import 'tables/assignments_table.dart';
import 'tables/chat_sessions_table.dart';
import 'tables/sync_state_table.dart';
import 'tables/class_groups_table.dart';
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
    ClassGroups,
    AppBuilderProjects,
    SyncState,
    Assignments,
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
    ClassGroupDao,
    AppBuilderProjectDao,
    SyncStateDao,
    AssignmentDao,
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
  int get schemaVersion => 15;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Not a drift table (drift has no FTS5 table class), so createAll
          // does not know about it.
          await _createResourceSearchIndex();
        },
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
          // ── Schema 9 onward: idempotent from here down ─────────────────
          //
          // `m.createTable(x)` always stamps *today's* Dart definition of x,
          // not the shape x had when it was first added — so any step below
          // that both creates a table and later ALTERs a column onto it can
          // collide with itself on a device that jumps several versions in
          // one boot (`duplicate column name`), and a step that re-runs
          // after a previous upgrade attempt partially completed and then
          // crashed can collide on `table already exists`. Both are real,
          // not hypothetical: the second is exactly what happened on a real
          // device here — `onUpgrade` has no transaction wrapping these
          // statements, so the schema-9→10 step (create appBuilderProjects)
          // had already committed and `user_version` was still 9 when the
          // schema-11 step below (the `UNIQUE`-column bug, since fixed)
          // threw and aborted the rest of the upgrade. Every step from here
          // down checks the database itself — via [_tableExists]/
          // [_columnExists] — instead of trusting `from`/`to`, so re-running
          // an upgrade that previously got partway is always safe.
          if (from < 9) {
            // Classes/streams. Additive: every existing learner starts
            // unassigned (class_group_id NULL) and keeps all their progress.
            if (!await _tableExists('class_groups')) {
              await m.createTable(classGroups);
            }
            if (!await _columnExists('students', 'class_group_id')) {
              await m.addColumn(students, students.classGroupId);
            }
            // Full-text index over teacher material. Built from the rows
            // already in topic_resources, so notes uploaded before this
            // upgrade stay searchable. Re-running the rebuild is harmless
            // (it is idempotent by nature), so this whole block is safe to
            // repeat even though the CREATE TABLE/TRIGGERs inside it are
            // already `IF NOT EXISTS`.
            await _createResourceSearchIndex();
            await customStatement(
              "INSERT INTO topic_resources_fts(topic_resources_fts) "
              "VALUES('rebuild')",
            );
          }
          if (from < 10) {
            // App Builder generations, saved per student — the same gap
            // Website Builder already closed via WebsiteProjects. Purely
            // additive: nothing previously read or wrote this table.
            if (!await _tableExists('app_builder_projects')) {
              await m.createTable(appBuilderProjects);
            }
          }
          if (from < 11) {
            // Scoped class/stream/subject sync over the local network
            // (lib/collaboration/sync/). classGroups.id and topic_resources
            // rows already existed and are device-local; the new columns
            // give them a portable identity/scope/version without touching
            // anything that already reads or writes these tables.
            if (!await _columnExists('class_groups', 'group_uuid')) {
              // No inline UNIQUE — see the doc on ClassGroups.groupUuid for
              // why (`ALTER TABLE ... ADD COLUMN ... UNIQUE` is rejected by
              // SQLite outright). Uniqueness is [idxClassGroupsGroupUuid],
              // created below once every row has a real value.
              await m.addColumn(classGroups, classGroups.groupUuid);
            }
            if (!await _columnExists('topic_resources', 'class_group_uuid')) {
              await m.addColumn(topicResources, topicResources.classGroupUuid);
            }
            if (!await _columnExists('topic_resources', 'updated_at')) {
              await m.addColumn(topicResources, topicResources.updatedAt);
            }
            if (!await _tableExists('sync_state')) {
              await m.createTable(syncState);
            }
            await classGroupDao.backfillGroupUuids();
            // Never carried by createTable regardless of which branch ran
            // above (see the standing note on idxTopicResourcesLookup), and
            // `CREATE UNIQUE INDEX` has no bare `IF NOT EXISTS` guard on
            // [Migrator.create] — check sqlite's own index list instead.
            if (!await _indexExists('idx_class_groups_group_uuid')) {
              await m.create(idxClassGroupsGroupUuid);
            }
          }
          if (from < 12) {
            // Assignments + rolling year progress
            // (AcademicScoreTrackerRepository). Additive: no existing
            // points/progress path (badges, topic_progress) reads or
            // writes this table.
            if (!await _tableExists('assignments')) {
              await m.createTable(assignments);
              await m.create(idxAssignmentsStudentSubjectTerm);
            }
          }
          if (from < 13) {
            // "Keep this chat" — see ChatSessions.pinned. Every existing
            // chat defaults to unpinned, so this changes nothing about
            // which chats age out until a student actually pins one.
            if (!await _columnExists('chat_sessions', 'pinned')) {
              await m.addColumn(chatSessions, chatSessions.pinned);
            }
          }
          if (from < 14) {
            // Lifetime Practice/Apply counters behind the Achievements
            // badge progress bars — see BadgeService. Every existing
            // learner starts these at 0, which reads as a contradiction
            // next to an already-earned badge (Sharp Mind shown Completed
            // beside a "0/5 correct" bar) — schema 15 below backfills a
            // floor from the badges already on record.
            if (!await _columnExists('students', 'total_practice_attempted')) {
              await m.addColumn(students, students.totalPracticeAttempted);
            }
            if (!await _columnExists('students', 'total_practice_correct')) {
              await m.addColumn(students, students.totalPracticeCorrect);
            }
            if (!await _columnExists('students', 'total_scenarios_completed')) {
              await m.addColumn(students, students.totalScenariosCompleted);
            }
            if (!await _columnExists('students', 'total_lessons_completed')) {
              await m.addColumn(students, students.totalLessonsCompleted);
            }
          }
          if (from < 15) {
            // Same standing rule as `if (from < 9)` above: check the
            // database itself, don't trust `from`. A device could reach
            // this block already sitting at schema 14 but missing a column
            // the 14-step added later in development — repeating the
            // guards here means the UPDATEs below never hit "no such
            // column" regardless of exactly which shape of v14 a real
            // install upgraded from.
            if (!await _columnExists('students', 'total_practice_attempted')) {
              await m.addColumn(students, students.totalPracticeAttempted);
            }
            if (!await _columnExists('students', 'total_practice_correct')) {
              await m.addColumn(students, students.totalPracticeCorrect);
            }
            if (!await _columnExists('students', 'total_scenarios_completed')) {
              await m.addColumn(students, students.totalScenariosCompleted);
            }
            if (!await _columnExists('students', 'total_lessons_completed')) {
              await m.addColumn(students, students.totalLessonsCompleted);
            }

            // Backfill for the schema-14 counters above, for a learner who
            // earned practice_starter/sharp_mind/scenario_solver under the
            // old session-scored logic before those counters existed.
            // Floors only (MAX, never overwrites a higher real count), so
            // this is safe to re-run and never contradicts activity BadgeService
            // has already recorded since the schema-14 upgrade. Guarded on
            // the table existing — always true on a real device (created at
            // schema 3) — because a synthetic test fixture that jumps
            // straight to an early schema may not have created it yet.
            if (await _tableExists('earned_badges')) {
              await customStatement('''
                UPDATE students SET total_practice_attempted =
                  MAX(total_practice_attempted, 1)
                WHERE id IN (
                  SELECT student_id FROM earned_badges
                  WHERE badge_id = 'practice_starter'
                )
              ''');
              await customStatement('''
                UPDATE students SET
                  total_practice_correct = MAX(total_practice_correct, 5),
                  total_practice_attempted = MAX(total_practice_attempted, 5)
                WHERE id IN (
                  SELECT student_id FROM earned_badges
                  WHERE badge_id = 'sharp_mind'
                )
              ''');
              await customStatement('''
                UPDATE students SET total_scenarios_completed =
                  MAX(total_scenarios_completed, 5)
                WHERE id IN (
                  SELECT student_id FROM earned_badges
                  WHERE badge_id = 'scenario_solver'
                )
              ''');
            }
          }
        },
      );

  Future<bool> _tableExists(String name) async {
    final row = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).getSingleOrNull();
    return row != null;
  }

  Future<bool> _indexExists(String name) async {
    final row = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?",
      variables: [Variable.withString(name)],
    ).getSingleOrNull();
    return row != null;
  }

  /// Whether [table] already has a column named [column] — the only check
  /// that can never be wrong about a table's actual shape, unlike inferring
  /// it from the migration version number (see the standing note above
  /// `if (from < 9)`). `pragma_table_info` is a read-only table-valued
  /// function, safe to query even mid-migration.
  Future<bool> _columnExists(String table, String column) async {
    final row = await customSelect(
      'SELECT 1 FROM pragma_table_info(?) WHERE name = ?',
      variables: [Variable.withString(table), Variable.withString(column)],
    ).getSingleOrNull();
    return row != null;
  }

  /// FTS5 index over `topic_resources` (title + chunk text), kept in sync by
  /// triggers so no write path can forget to update it.
  ///
  /// External-content table: the text lives once, in `topic_resources`; the
  /// index holds only tokens, keyed by `rowid = topic_resources.id`. The
  /// porter tokenizer folds inflections ("chemicals" → "chemical",
  /// "evaporating" → "evaporation") — see `TopicResourceDao.searchChunks`
  /// for how derived forms it misses are caught with prefix terms.
  ///
  /// FTS5 comes from the SQLite build `sqlite3_flutter_libs` ships; no extra
  /// dependency.
  Future<void> _createResourceSearchIndex() async {
    await customStatement(
      "CREATE VIRTUAL TABLE IF NOT EXISTS topic_resources_fts USING fts5("
      "resource_title, content_chunk, "
      "content='topic_resources', content_rowid='id', "
      "tokenize='porter unicode61')",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS topic_resources_fts_ai '
      'AFTER INSERT ON topic_resources BEGIN '
      '  INSERT INTO topic_resources_fts(rowid, resource_title, content_chunk) '
      '  VALUES (new.id, new.resource_title, new.content_chunk); '
      'END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS topic_resources_fts_ad '
      'AFTER DELETE ON topic_resources BEGIN '
      "  INSERT INTO topic_resources_fts(topic_resources_fts, rowid, "
      '    resource_title, content_chunk) '
      "  VALUES ('delete', old.id, old.resource_title, old.content_chunk); "
      'END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS topic_resources_fts_au '
      'AFTER UPDATE ON topic_resources BEGIN '
      "  INSERT INTO topic_resources_fts(topic_resources_fts, rowid, "
      '    resource_title, content_chunk) '
      "  VALUES ('delete', old.id, old.resource_title, old.content_chunk); "
      '  INSERT INTO topic_resources_fts(rowid, resource_title, content_chunk) '
      '  VALUES (new.id, new.resource_title, new.content_chunk); '
      'END',
    );
  }

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await resolveAppStorageDirectory();
      final file = File(p.join(dir.path, 'otic_student_db.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        setup: (db) {
          // WAL lets a translation-cache lookup or a chat-session read run
          // while a session/badge write is still in flight, instead of
          // queuing behind SQLite's default rollback-journal lock — this is
          // a chat app that reads and writes on every turn. NORMAL sync is
          // the standard WAL pairing: still crash-safe (readers never see a
          // torn page), just not fsync-per-commit.
          db.execute('PRAGMA journal_mode=WAL;');
          db.execute('PRAGMA synchronous=NORMAL;');
          // A few MB of page cache for a database that stays under ~10 MB
          // on-device — cheap, and keeps hot tables (translation cache,
          // topic_resources_fts) resident instead of re-hitting disk.
          db.execute('PRAGMA cache_size=-8000;');
          db.execute('PRAGMA temp_store=MEMORY;');
        },
      );
    });
  }
}
