import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/gamification/badge_service.dart';

/// Scoring is only worth anything if it reflects what the student actually
/// did, in whichever mode they did it, and if Achievements shows it without a
/// restart. Both of those failed silently before — badges were written to
/// SQLite correctly while the screen kept serving a cached empty list, and the
/// streak only moved when a Learn-path lesson completed. Nothing threw, so
/// only a test against the real database and a real container catches it.
void main() {
  late OticDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    container = ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);
    await db.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina', language: const Value('en')),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('any mode counts as an active day', () {
    test('a practice answer starts the streak', () async {
      final before = await db.studentDao.getStudentById(1);
      expect(before!.streakDays, 0);

      await container.read(badgeServiceProvider).onPracticeAnswered(1, 1);

      final after = await db.studentDao.getStudentById(1);
      expect(after!.streakDays, 1);
      expect(after.lastStreakDate, isNotNull);
    });

    test('saving a project starts the streak', () async {
      await container.read(badgeServiceProvider).onProjectSaved(1);
      expect((await db.studentDao.getStudentById(1))!.streakDays, 1);
    });

    test('an apply scenario starts the streak', () async {
      await container.read(badgeServiceProvider).onApplyEvaluated(1, 1);
      expect((await db.studentDao.getStudentById(1))!.streakDays, 1);
    });

    test('more activity the same day does not inflate it', () async {
      final svc = container.read(badgeServiceProvider);
      await svc.onPracticeAnswered(1, 1);
      await svc.onPracticeAnswered(1, 2);
      await svc.onApplyEvaluated(1, 1);
      expect((await db.studentDao.getStudentById(1))!.streakDays, 1);
    });
  });

  test('a badge earned outside the learn path reaches the screen at once',
      () async {
    // Read first so both providers cache — that cache is what used to go
    // stale until the app restarted.
    expect(await container.read(earnedBadgesProvider(1).future), isEmpty);
    expect((await container.read(activeStudentProvider.future))!.totalPoints, 0);

    await container.read(badgeServiceProvider).onPracticeAnswered(1, 1);

    final badges = await container.read(earnedBadgesProvider(1).future);
    final student = await container.read(activeStudentProvider.future);
    expect(badges.map((b) => b.badgeId), contains('practice_starter'));
    expect(student!.totalPoints, 30);
    expect(student.streakDays, 1);
  });

  group('what a student earned survives', () {
    test('re-running onboarding does not strand their badges', () async {
      // Earn something first.
      await container.read(badgeServiceProvider).onPracticeAnswered(1, 5);
      final earnedBefore = await db.badgeDao.getBadgesForStudent(1);
      final pointsBefore =
          (await db.studentDao.getStudentById(1))!.totalPoints;
      expect(earnedBefore, isNotEmpty);
      expect(pointsBefore, greaterThan(0));

      // Onboarding reached again — e.g. the router's profile lookup timed out
      // on a slow cold start. This must edit the profile, never add a second.
      await container
          .read(studentNotifierProvider.notifier)
          .createProfile(name: 'Amina', language: 'sw');

      expect((await db.studentDao.getAllStudents()).length, 1);

      final active = await db.studentDao.getActiveStudent();
      expect(active!.id, 1);
      expect(active.totalPoints, pointsBefore);
      expect(active.streakDays, 1);
      expect(active.language, 'sw', reason: 'the new choice still applies');
      expect(
        (await db.badgeDao.getBadgesForStudent(active.id)).map((b) => b.badgeId),
        containsAll(earnedBefore.map((b) => b.badgeId)),
      );
    });

    test('earning continues on top of what is already stored', () async {
      final svc = container.read(badgeServiceProvider);
      await svc.onPracticeAnswered(1, 5); // practice_starter + sharp_mind
      final midway = (await db.studentDao.getStudentById(1))!.totalPoints;

      await svc.onProjectSaved(1); // creator, on top
      final after = (await db.studentDao.getStudentById(1))!;

      expect(after.totalPoints, greaterThan(midway));
      expect(
        (await db.badgeDao.getBadgesForStudent(1)).map((b) => b.badgeId),
        containsAll(['practice_starter', 'sharp_mind', 'creator']),
      );
    });
  });

  test('no trigger can award the removed teach badge', () async {
    final svc = container.read(badgeServiceProvider);
    await svc.onPracticeAnswered(1, 9);
    await svc.onApplyEvaluated(1, 9);
    await svc.onProjectSaved(1);

    final badges = await db.badgeDao.getBadgesForStudent(1);
    expect(badges.map((b) => b.badgeId), isNot(contains('teacher')));
  });
}
