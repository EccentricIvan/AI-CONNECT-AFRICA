import 'dart:io';

import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Regression coverage for `MigrationStrategy.onUpgrade` — the one path this
/// project otherwise never exercises. Every DAO test opens a fresh in-memory
/// database (`OticDatabase.forTesting`), which always takes the `onCreate`
/// branch (`m.createAll()`), because a brand-new database's `user_version`
/// starts at 0 and jumps straight to the current [OticDatabase.schemaVersion].
/// `onUpgrade` — the step-by-step `if (from < N)` ladder — only runs on a
/// device that already has data from an older version, and nothing here had
/// ever actually run it before this file existed.
///
/// That gap is exactly how `ClassGroups.groupUuid` shipped as `UNIQUE` on the
/// column: `onCreate`'s `CREATE TABLE ... UNIQUE` is legal SQLite and passed
/// every existing test; `onUpgrade`'s `ALTER TABLE ... ADD COLUMN ... UNIQUE`
/// is not legal SQLite (`SqliteException(1): Cannot add a UNIQUE column`) and
/// nothing here ran it until a real upgrading device did. The same class of
/// gap is what let schema 14's counters ship starting every existing learner
/// at 0 even when they already held the badge those counters back — see the
/// schema-15 tests below.
void main() {
  test('upgrading a pre-11 database does not throw on ClassGroups.groupUuid',
      () async {
    // The relevant slice of schema 10 — enough for the full 10→N upgrade
    // ladder to run for real (every `if (from < N)` step in between fires
    // too, not just schema 11's), not the whole database. Includes a
    // pre-existing class/stream row — the exact case the migration's own
    // backfill has to handle: one that predates `group_uuid` entirely.
    final db = OticDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory(setup: (rawDb) {
        rawDb.execute('''
          CREATE TABLE students (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            total_points INTEGER NOT NULL DEFAULT 0,
            class_group_id INTEGER
          );
          CREATE TABLE class_groups (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            stream_name TEXT,
            created_at INTEGER NOT NULL
          );
          CREATE TABLE topic_resources (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            subject_id TEXT NOT NULL,
            topic_key TEXT NOT NULL,
            term_marker INTEGER NOT NULL DEFAULT 0,
            resource_title TEXT NOT NULL,
            content_chunk TEXT NOT NULL,
            created_at TEXT NOT NULL
          );
          CREATE TABLE chat_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            student_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            topic TEXT NOT NULL DEFAULT '',
            preview TEXT NOT NULL DEFAULT '',
            stage TEXT NOT NULL DEFAULT 'answer',
            turn_count INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
          INSERT INTO class_groups (id, class_name, stream_name, created_at)
          VALUES (1, 'S2', 'East', 0);
          PRAGMA user_version = 10;
        ''');
      })),
    );

    // Triggers drift's `beforeOpen`, which compares `user_version` (10)
    // against `schemaVersion` and runs `onUpgrade(m, 10, schemaVersion)` —
    // the exact call that used to throw `SqliteException(1)`.
    final groups = await db.classGroupDao.watchAllClasses().first;

    expect(groups, hasLength(1));
    expect(groups.single.groupUuid, isNotNull,
        reason: 'the schema-11 backfill must give every pre-existing '
            'class/stream a group_uuid, not just new ones');

    await db.close();
  });

  test(
      'reopening a database stuck mid-upgrade finishes instead of throwing '
      'on tables/columns it already has', () async {
    // The exact state a real device on this machine was found in: an
    // earlier launch ran the schema-9→10 step (created app_builder_projects)
    // and then crashed on schema-11's UNIQUE-column bug before
    // `user_version` was ever bumped past 9 — `onUpgrade` issues each
    // statement outside of one wrapping transaction, so the completed part
    // stayed committed. The next launch must heal this, not throw
    // `table app_builder_projects already exists` on the same `from < 10`
    // step it re-enters.
    final db = OticDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory(setup: (rawDb) {
        rawDb.execute('''
          CREATE TABLE students (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            total_points INTEGER NOT NULL DEFAULT 0,
            class_group_id INTEGER
          );
          CREATE TABLE class_groups (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            class_name TEXT NOT NULL,
            stream_name TEXT,
            created_at INTEGER NOT NULL
          );
          CREATE TABLE topic_resources (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            subject_id TEXT NOT NULL,
            topic_key TEXT NOT NULL,
            term_marker INTEGER NOT NULL DEFAULT 0,
            resource_title TEXT NOT NULL,
            content_chunk TEXT NOT NULL,
            created_at TEXT NOT NULL
          );
          CREATE TABLE chat_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            student_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            topic TEXT NOT NULL DEFAULT '',
            preview TEXT NOT NULL DEFAULT '',
            stage TEXT NOT NULL DEFAULT 'answer',
            turn_count INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
          -- Already created by the crashed run's schema-9→10 step, while
          -- user_version below still reads 9 — the actual observed state.
          CREATE TABLE app_builder_projects (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            app_type_id TEXT NOT NULL,
            app_type_name TEXT NOT NULL,
            theme_color TEXT NOT NULL DEFAULT '#2563EB',
            html_content TEXT NOT NULL,
            backend_content TEXT,
            answers_json TEXT NOT NULL DEFAULT '{}',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
          INSERT INTO class_groups (id, class_name, stream_name, created_at)
          VALUES (1, 'S2', 'East', 0);
          PRAGMA user_version = 9;
        ''');
      })),
    );

    // Must not throw `table app_builder_projects already exists`.
    final groups = await db.classGroupDao.watchAllClasses().first;
    expect(groups.single.groupUuid, isNotNull);

    await db.close();
  });

  test('an existing v13 database upgrades to v14 without throwing, and the '
      'new student columns default to 0', () async {
    final dir = await Directory.systemTemp.createTemp('otic_migration_test');
    final file = File(p.join(dir.path, 'test.sqlite'));
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    // Build a real, fully-current database first (exercises onCreate), then
    // strip it back down to what a v13 install actually looks like. That
    // way the "v13 shape" here is derived from the real schema instead of
    // hand-typed and possibly wrong.
    final seed = OticDatabase.forTesting(NativeDatabase(file));
    await seed.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina'),
    );
    for (final column in [
      'total_practice_attempted',
      'total_practice_correct',
      'total_scenarios_completed',
      'total_lessons_completed',
    ]) {
      await seed.customStatement('ALTER TABLE students DROP COLUMN $column');
    }
    await seed.customStatement('PRAGMA user_version = 13');
    await seed.close();

    // Reopening against the same file is what should trigger onUpgrade.
    final upgraded = OticDatabase.forTesting(NativeDatabase(file));
    final student = await upgraded.studentDao.getStudentById(1);
    expect(student, isNotNull);
    expect(student!.name, 'Amina');
    expect(student.totalPracticeAttempted, 0);
    expect(student.totalPracticeCorrect, 0);
    expect(student.totalScenariosCompleted, 0);
    expect(student.totalLessonsCompleted, 0);
    await upgraded.customStatement('PRAGMA user_version = 13');
    await upgraded.close();

    // Re-running the same upgrade (e.g. a device that jumps versions twice)
    // must stay a no-op, not throw on "duplicate column name" — see the
    // standing note in otic_database.dart on why every step here is guarded.
    final reupgraded = OticDatabase.forTesting(NativeDatabase(file));
    expect(
      (await reupgraded.studentDao.getStudentById(1))!.totalPracticeAttempted,
      0,
    );
    await reupgraded.close();
  });

  test('a badge earned before schema 14 backfills its counter on upgrade, '
      'instead of showing Completed next to a 0/5 bar', () async {
    final dir = await Directory.systemTemp.createTemp('otic_migration_test');
    final file = File(p.join(dir.path, 'test.sqlite'));
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final seed = OticDatabase.forTesting(NativeDatabase(file));
    await seed.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina'),
    );
    // Earned under the old session-scored logic, before the schema-14
    // counters existed to record it — earned_badges' shape is unchanged
    // across 13/14/15, so this is exactly what a real pre-14 install has.
    await seed.badgeDao.awardBadge(
      studentId: 1,
      badgeId: 'sharp_mind',
      badgeName: 'Sharp Mind',
    );
    for (final column in [
      'total_practice_attempted',
      'total_practice_correct',
      'total_scenarios_completed',
      'total_lessons_completed',
    ]) {
      await seed.customStatement('ALTER TABLE students DROP COLUMN $column');
    }
    await seed.customStatement('PRAGMA user_version = 13');
    await seed.close();

    final upgraded = OticDatabase.forTesting(NativeDatabase(file));
    final student = await upgraded.studentDao.getStudentById(1);
    expect(student!.totalPracticeCorrect, 5);
    expect(student.totalPracticeAttempted, 5);
    await upgraded.close();
  });

  test('a device already at schema 14 but missing a column that step later '
      'grew is still repaired by the schema-15 step, not left to throw '
      "'no such column' on every read", () async {
    final dir = await Directory.systemTemp.createTemp('otic_migration_test');
    final file = File(p.join(dir.path, 'test.sqlite'));
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final seed = OticDatabase.forTesting(NativeDatabase(file));
    await seed.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina'),
    );
    // Only the one column schema 14 grew last is missing — simulating a
    // device that upgraded partway through schema 14's development.
    await seed.customStatement(
        'ALTER TABLE students DROP COLUMN total_lessons_completed');
    await seed.customStatement('PRAGMA user_version = 14');
    await seed.close();

    final upgraded = OticDatabase.forTesting(NativeDatabase(file));
    final student = await upgraded.studentDao.getStudentById(1);
    expect(student, isNotNull);
    expect(student!.totalLessonsCompleted, 0);
    await upgraded.close();
  });
}
