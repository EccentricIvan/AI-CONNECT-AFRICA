import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_connect_africa/curriculum/lesson_progress.dart';
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

      await container
          .read(badgeServiceProvider)
          .onPracticeAnswered(1, attempted: 1, correct: 1);

      final after = await db.studentDao.getStudentById(1);
      expect(after!.streakDays, 1);
      expect(after.lastStreakDate, isNotNull);
    });

    test('saving a project starts the streak', () async {
      await container.read(badgeServiceProvider).onProjectSaved(1);
      expect((await db.studentDao.getStudentById(1))!.streakDays, 1);
    });

    test('an apply scenario starts the streak', () async {
      await container.read(badgeServiceProvider).onApplyEvaluated(1);
      expect((await db.studentDao.getStudentById(1))!.streakDays, 1);
    });

    test('more activity the same day does not inflate it', () async {
      final svc = container.read(badgeServiceProvider);
      await svc.onPracticeAnswered(1, attempted: 1, correct: 1);
      await svc.onPracticeAnswered(1, attempted: 1, correct: 1);
      await svc.onApplyEvaluated(1);
      expect((await db.studentDao.getStudentById(1))!.streakDays, 1);
    });
  });

  test('a badge earned outside the learn path reaches the screen at once',
      () async {
    // Read first so both providers cache — that cache is what used to go
    // stale until the app restarted.
    expect(await container.read(earnedBadgesProvider(1).future), isEmpty);
    expect((await container.read(activeStudentProvider.future))!.totalPoints, 0);

    await container
        .read(badgeServiceProvider)
        .onPracticeAnswered(1, attempted: 1, correct: 1);

    final badges = await container.read(earnedBadgesProvider(1).future);
    final student = await container.read(activeStudentProvider.future);
    expect(badges.map((b) => b.badgeId), contains('practice_starter'));
    expect(student!.totalPoints, 30);
    expect(student.streakDays, 1);
  });

  test(
      'a counter-only update reaches studentStatsProvider without '
      'touching activeStudentProvider', () async {
    // activeStudentProvider is watched by chat, the router and the app
    // shell — invalidating it on every practice answer would rebuild all
    // of that just to move a counter, so BadgeService is expected to leave
    // it alone here and refresh studentStatsProvider instead.
    final statsSub = container.listen(studentStatsProvider(1), (_, __) {});
    addTearDown(statsSub.close);
    // A listener kept alive is what makes invalidate() actually trigger a
    // rebuild we can count — without one, invalidating a provider nobody is
    // watching just marks it stale until something happens to read it next,
    // which would make this assertion pass by accident either way.
    var activeRebuilds = 0;
    final activeSub = container.listen(activeStudentProvider, (_, __) {
      activeRebuilds++;
    });
    addTearDown(activeSub.close);
    final svc = container.read(badgeServiceProvider);

    // First call earns practice_starter and starts the streak, both of
    // which legitimately touch activeStudentProvider — get that out of the
    // way before observing the counter-only path.
    await svc.onPracticeAnswered(1, attempted: 1, correct: 0);
    await container.read(activeStudentProvider.future);
    activeRebuilds = 0;

    // Second call: practice_starter is already owned and the streak was
    // already touched today, so nothing awards and only the counter-only
    // refresh path runs.
    await svc.onPracticeAnswered(1, attempted: 1, correct: 0);

    final stats = await container.read(studentStatsProvider(1).future);
    expect(stats!.totalPracticeAttempted, 2);
    expect(activeRebuilds, 0,
        reason: 'a counter-only update invalidated activeStudentProvider');
  });

  group('what a student earned survives', () {
    test('re-running onboarding does not strand their badges', () async {
      // Earn something first.
      await container
          .read(badgeServiceProvider)
          .onPracticeAnswered(1, attempted: 5, correct: 5);
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
      // practice_starter + sharp_mind
      await svc.onPracticeAnswered(1, attempted: 5, correct: 5);
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

  group('curriculum lessons, scoped per student', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('revisiting a passed lesson does not re-count it', () async {
      final lp = LessonProgress();
      final svc = container.read(badgeServiceProvider);

      final first = await lp.markCompleteFor(1, 'physics', 0, 0);
      expect(first, isTrue);
      await svc.onCurriculumLessonCompleted(1);

      final second = await lp.markCompleteFor(1, 'physics', 0, 0);
      expect(second, isFalse);

      expect((await db.studentDao.getStudentById(1))!.totalLessonsCompleted, 1);
    });

    test('two different students completing the same lesson both count',
        () async {
      await db.studentDao.createStudent(
        StudentsCompanion.insert(name: 'Brian', language: const Value('en')),
      );
      final lp = LessonProgress();

      expect(await lp.markCompleteFor(1, 'physics', 0, 0), isTrue);
      expect(await lp.markCompleteFor(2, 'physics', 0, 0), isTrue,
          reason: 'a shared device must not credit one learner\'s lesson '
              'to another');
    });
  });

  group('lifetime counters, not session-scoped', () {
    test('five correct answers across separate calls earns sharp_mind',
        () async {
      final svc = container.read(badgeServiceProvider);
      for (var i = 0; i < 5; i++) {
        await svc.onPracticeAnswered(1, attempted: 1, correct: 1);
      }
      final student = (await db.studentDao.getStudentById(1))!;
      expect(student.totalPracticeCorrect, 5);
      expect(
        (await db.badgeDao.getBadgesForStudent(1)).map((b) => b.badgeId),
        contains('sharp_mind'),
      );
    });

    test('ten wrong answers never earns sharp_mind but still count attempts',
        () async {
      final svc = container.read(badgeServiceProvider);
      for (var i = 0; i < 10; i++) {
        await svc.onPracticeAnswered(1, attempted: 1, correct: 0);
      }
      final student = (await db.studentDao.getStudentById(1))!;
      expect(student.totalPracticeAttempted, 10);
      expect(student.totalPracticeCorrect, 0);
      expect(
        (await db.badgeDao.getBadgesForStudent(1)).map((b) => b.badgeId),
        isNot(contains('sharp_mind')),
      );
    });

    test('scenario_solver needs a fifth separate evaluation', () async {
      final svc = container.read(badgeServiceProvider);
      for (var i = 0; i < 4; i++) {
        await svc.onApplyEvaluated(1);
      }
      expect(
        (await db.badgeDao.getBadgesForStudent(1)).map((b) => b.badgeId),
        isNot(contains('scenario_solver')),
      );
      await svc.onApplyEvaluated(1);
      expect(
        (await db.badgeDao.getBadgesForStudent(1)).map((b) => b.badgeId),
        contains('scenario_solver'),
      );
    });
  });

  test('no trigger can award the removed teach badge', () async {
    final svc = container.read(badgeServiceProvider);
    await svc.onPracticeAnswered(1, attempted: 9, correct: 9);
    await svc.onApplyEvaluated(1);
    await svc.onProjectSaved(1);

    final badges = await db.badgeDao.getBadgesForStudent(1);
    expect(badges.map((b) => b.badgeId), isNot(contains('teacher')));
  });
}
