import 'package:drift/drift.dart' show Value;
import '../db/otic_database.dart';
import '../db/providers/db_provider.dart';
import 'badge_definitions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Checks eligibility and awards badges, adding points to the student.
/// Call these methods after the triggering action completes.
class BadgeService {
  BadgeService(this._db, this._ref);
  final OticDatabase _db;
  final Ref _ref;

  // ── Trigger: a lesson was marked complete ─────────────────────────────────

  Future<List<BadgeDef>> onLessonCompleted(int studentId) async {
    final awarded = await _touchStreak(studentId);
    final paths = await _db.pathDao.getPathsForStudent(studentId);
    final totalCompleted =
        paths.fold(0, (s, p) => s + p.completedLessons);

    // First lesson ever
    if (totalCompleted == 1) {
      await _award(studentId, 'first_lesson', awarded);
    }

    // Any path fully complete
    final hasFullPath = paths.any((p) => p.completedLessons == p.totalLessons);
    if (hasFullPath) {
      await _award(studentId, 'path_master', awarded);
    }

    // 3 distinct paths started
    if (paths.length >= 3) {
      await _award(studentId, 'polymath', awarded);
    }

    return awarded;
  }

  // ── Trigger: a curriculum-browser lesson was passed ──────────────────────

  /// Separate from [onLessonCompleted] (auto-generated LearningPaths) —
  /// the curriculum browser tracks its own lessons via LessonProgress.
  /// Only call this when `LessonProgress.markCompleteFor` returned true, so
  /// revisiting an already-passed lesson never re-counts it.
  Future<List<BadgeDef>> onCurriculumLessonCompleted(int studentId) async {
    final awarded = await _touchStreak(studentId);
    final student = await _db.studentDao.getStudentById(studentId);
    if (student == null) return awarded;

    await _db.studentDao.updateStudent(StudentsCompanion(
      id: Value(studentId),
      totalLessonsCompleted: Value(student.totalLessonsCompleted + 1),
    ));
    _refreshStats(studentId);

    await _award(studentId, 'first_lesson', awarded);
    return awarded;
  }

  // ── Trigger: practice exercise(s) answered ───────────────────────────────

  /// [attempted]/[correct] are the counts from *this* event (1/0 or 1/1 for
  /// a single quiz question, or a whole quiz's totals at once) — they are
  /// added to the student's lifetime counters, never treated as the total
  /// themselves, so re-entering Practice never double counts or resets what
  /// the Achievements screen shows.
  Future<List<BadgeDef>> onPracticeAnswered(
    int studentId, {
    required int attempted,
    required int correct,
  }) async {
    final awarded = await _touchStreak(studentId);
    final student = await _db.studentDao.getStudentById(studentId);
    if (student == null) return awarded;

    await _db.studentDao.updateStudent(StudentsCompanion(
      id: Value(studentId),
      totalPracticeAttempted:
          Value(student.totalPracticeAttempted + attempted),
      totalPracticeCorrect: Value(student.totalPracticeCorrect + correct),
    ));
    _refreshStats(studentId);

    await _award(studentId, 'practice_starter', awarded);
    if (student.totalPracticeCorrect + correct >= 5) {
      await _award(studentId, 'sharp_mind', awarded);
    }
    return awarded;
  }

  // ── Trigger: apply scenario evaluated ────────────────────────────────────

  Future<List<BadgeDef>> onApplyEvaluated(int studentId) async {
    final awarded = await _touchStreak(studentId);
    final student = await _db.studentDao.getStudentById(studentId);
    if (student == null) return awarded;

    final total = student.totalScenariosCompleted + 1;
    await _db.studentDao.updateStudent(StudentsCompanion(
      id: Value(studentId),
      totalScenariosCompleted: Value(total),
    ));
    _refreshStats(studentId);

    if (total >= 5) {
      await _award(studentId, 'scenario_solver', awarded);
    }
    return awarded;
  }

  // ── Trigger: project saved ────────────────────────────────────────────────

  Future<List<BadgeDef>> onProjectSaved(int studentId,
      {bool fullStack = false}) async {
    final awarded = await _touchStreak(studentId);
    await _award(studentId, 'creator', awarded);
    if (fullStack) await _award(studentId, 'full_stack_builder', awarded);
    return awarded;
  }

  // ── Trigger: a project was exported / moved out of the app ───────────────

  Future<List<BadgeDef>> onProjectExported(int studentId) async {
    final awarded = await _touchStreak(studentId);
    await _award(studentId, 'shipped_it', awarded);
    return awarded;
  }

  // ── Internal: bump the daily streak from any learning-mode activity ──────

  /// Every trigger above routes through here, so a day counts as active
  /// whichever mode the student used — not only a completed path lesson.
  Future<List<BadgeDef>> _touchStreak(int studentId) async {
    final awarded = <BadgeDef>[];
    final streak = await updateStreak(studentId);
    if (streak >= 7) {
      await _award(studentId, 'consistent_learner', awarded);
    }
    return awarded;
  }

  // ── Internal: award badge + add points if not already owned ──────────────

  Future<void> _award(
      int studentId, String badgeId, List<BadgeDef> collected) async {
    final alreadyHas = await _db.badgeDao.hasBadge(studentId, badgeId);
    if (alreadyHas) return;

    final def = badgeById(badgeId);
    if (def == null) return;

    await _db.badgeDao.awardBadge(
      studentId: studentId,
      badgeId: def.id,
      badgeName: def.name,
    );

    // Add points to student
    if (def.points > 0) {
      final student = await _db.studentDao.getStudentById(studentId);
      if (student != null) {
        final newPoints = student.totalPoints + def.points;
        await _db.studentDao.updateStudent(
          StudentsCompanion(id: Value(studentId), totalPoints: Value(newPoints)),
        );
        // Century badge
        if (newPoints >= 100) {
          await _award(studentId, 'century', collected);
        }
      }
    }

    collected.add(def);

    // Achievements reads badges/points through FutureProviders that cache until
    // invalidated — without this an award made outside the Learn-path flow only
    // shows up after a restart.
    _refreshAchievements(studentId);
  }

  void _refreshAchievements(int studentId) {
    _ref.invalidate(earnedBadgesProvider(studentId));
    _ref.invalidate(activeStudentProvider);
    _refreshStats(studentId);
  }

  /// Achievements-only refresh — see [studentStatsProvider]. Every write to
  /// the student row goes through here or [_refreshAchievements] so the
  /// screen never shows a stale counter, without rebuilding the rest of the
  /// app on every practice answer.
  void _refreshStats(int studentId) {
    _ref.invalidate(studentStatsProvider(studentId));
  }

  /// Update streak — call once per day at first interaction.
  Future<int> updateStreak(int studentId) async {
    final student = await _db.studentDao.getStudentById(studentId);
    if (student == null) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = student.lastStreakDate;

    int newStreak = student.streakDays;

    if (lastDate == null) {
      newStreak = 1;
    } else {
      final lastDay =
          DateTime(lastDate.year, lastDate.month, lastDate.day);
      final diff = today.difference(lastDay).inDays;
      if (diff == 1) {
        newStreak = student.streakDays + 1;
      } else if (diff > 1) {
        newStreak = 1; // streak broken
      }
      // diff == 0 means already updated today, no change
    }

    await _db.studentDao.updateStudent(
      StudentsCompanion(
        id: Value(studentId),
        streakDays: Value(newStreak),
        lastStreakDate: Value(today),
      ),
    );

    if (newStreak != student.streakDays) _refreshAchievements(studentId);

    return newStreak;
  }
}

final badgeServiceProvider = Provider<BadgeService>((ref) {
  final db = ref.watch(dbProvider);
  return BadgeService(db, ref);
});
