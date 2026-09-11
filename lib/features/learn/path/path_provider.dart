import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai_core/providers/ai_provider.dart';
import '../../../ai_core/tutor/programming_topic.dart';
import '../../../db/providers/db_provider.dart';
import '../../../db/otic_database.dart';
import '../../../gamification/badge_service.dart';
import 'path_generator.dart';
import 'path_models.dart';

// ── All paths for active student ─────────────────────────────────────────────

final studentPathsProvider = FutureProvider<List<LearningPath>>((ref) async {
  final student = await ref.watch(activeStudentProvider.future);
  if (student == null) return [];
  final db = ref.watch(dbProvider);
  return db.pathDao.getPathsForStudent(student.id);
});

/// Converts a DB row into a rich [ParsedPath].
ParsedPath parsedFromRow(LearningPath row) => ParsedPath.fromDb(
      topic: row.topic,
      title: row.title,
      description: row.description,
      unitsJson: row.unitsJson,
    );

// ── Single path by topic ──────────────────────────────────────────────────────

final pathByTopicProvider =
    FutureProvider.family<LearningPath?, String>((ref, topic) async {
  final student = await ref.watch(activeStudentProvider.future);
  if (student == null) return null;
  final db = ref.watch(dbProvider);
  return db.pathDao.getPath(student.id, topic);
});

// ── Path generation + management ─────────────────────────────────────────────

class PathNotifier extends AsyncNotifier<List<LearningPath>> {
  @override
  Future<List<LearningPath>> build() async {
    final student = await ref.watch(activeStudentProvider.future);
    if (student == null) return [];
    final db = ref.watch(dbProvider);
    return db.pathDao.getPathsForStudent(student.id);
  }

  /// Generate (or regenerate) a path for [topic] and save it to DB.
  Future<ParsedPath> generatePath(String topic) async {
    final student = await ref.read(activeStudentProvider.future);
    if (student == null) throw StateError('No student profile');

    final engine = looksLikeProgramming(topic)
        ? await ref.read(programmingEngineProvider.future)
        : await ref.read(engineLoadedProvider.future);
    final db = ref.read(dbProvider);
    final generator = PathGenerator(engine: engine);

    // Get current mastery to calibrate difficulty
    final progress = await db.sessionDao.getTopicProgress(student.id);
    final mastery = progress
        .where((p) => p.topic == topic)
        .fold(0, (_, p) => p.level);

    final parsed = await generator.generate(
      topic: topic,
      student: student,
      currentMasteryLevel: mastery,
    );
    final localized = await _localizePath(ref, parsed);

    await db.pathDao.upsertPath(LearningPathsCompanion.insert(
      studentId: student.id,
      topic: topic,
      title: localized.title,
      description: localized.description,
      unitsJson: Value(localized.unitsToJson()),
      totalLessons: Value(localized.totalLessons),
      completedLessons: const Value(0),
      generatedAt: Value(DateTime.now()),
      lastAccessedAt: Value(DateTime.now()),
    ));

    ref.invalidate(studentPathsProvider);
    ref.invalidate(pathByTopicProvider(topic));
    return localized;
  }

  /// Mark a lesson complete and advance the pointer.
  Future<void> completeLesson({
    required int pathId,
    required ParsedPath parsed,
    required int unitIndex,
    required int lessonIndex,
  }) async {
    final updatedUnits = List<PathUnit>.from(parsed.units);
    final unit = updatedUnits[unitIndex];
    final updatedLessons = List<PathLesson>.from(unit.lessons);
    updatedLessons[lessonIndex] =
        updatedLessons[lessonIndex].copyWith(isCompleted: true);
    updatedUnits[unitIndex] = unit.copyWith(lessons: updatedLessons);

    final updatedPath = ParsedPath(
      topic: parsed.topic,
      title: parsed.title,
      description: parsed.description,
      units: updatedUnits,
    );

    // Advance to next incomplete lesson
    int nextUnit = unitIndex;
    int nextLesson = lessonIndex + 1;
    if (nextLesson >= unit.lessons.length) {
      nextUnit = unitIndex + 1;
      nextLesson = 0;
    }
    if (nextUnit >= parsed.units.length) {
      nextUnit = unitIndex;
      nextLesson = lessonIndex;
    }

    final db = ref.read(dbProvider);
    await db.pathDao.markLessonComplete(
      pathId: pathId,
      unitIndex: unitIndex,
      lessonIndex: lessonIndex,
      updatedUnitsJson: updatedPath.unitsToJson(),
      completedLessons: updatedPath.completedLessons,
      nextUnit: nextUnit,
      nextLesson: nextLesson,
    );

    ref.invalidate(studentPathsProvider);

    // Badges/streak were defined but never triggered anywhere — this is the
    // one place every lesson completion flows through, so hook them in here.
    final student = await ref.read(activeStudentProvider.future);
    if (student != null) {
      final badges = ref.read(badgeServiceProvider);
      await badges.onLessonCompleted(student.id);
      final streak = await badges.updateStreak(student.id);
      await badges.onStreakUpdated(student.id, streak);
      ref.invalidate(activeStudentProvider);
    }
  }
}

Future<ParsedPath> _localizePath(Ref ref, ParsedPath path) async {
  final strings = <String>[
    path.title,
    path.description,
    for (final unit in path.units) ...[
      unit.title,
      for (final lesson in unit.lessons) lesson.title,
    ],
  ];
  final out = await localizeMany(ref, strings);
  var i = 0;
  final title = out[i++];
  final description = out[i++];
  final units = [
    for (final unit in path.units)
      PathUnit(
        title: out[i++],
        lessons: [
          for (final lesson in unit.lessons)
            PathLesson(title: out[i++], isCompleted: lesson.isCompleted),
        ],
      ),
  ];
  return ParsedPath(
    topic: path.topic,
    title: title,
    description: description,
    units: units,
  );
}

final pathNotifierProvider =
    AsyncNotifierProvider<PathNotifier, List<LearningPath>>(PathNotifier.new);
