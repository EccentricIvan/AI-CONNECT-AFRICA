import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LessonProgress {
  static const _prefix = 'lesson_done_';

  Future<void> markComplete(String subjectId, int unitIndex, int lessonIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix${subjectId}_${unitIndex}_$lessonIndex', true);
  }

  /// Per-student variant of [markComplete] — on a shared device, "done" for
  /// one learner must never read as done for another. Returns true only the
  /// first time this lesson is marked for this student, so a badge/counter
  /// caller can tell a genuine first completion from a revisit.
  Future<bool> markCompleteFor(
      int studentId, String subjectId, int unitIndex, int lessonIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_prefix}s${studentId}_${subjectId}_${unitIndex}_$lessonIndex';
    if (prefs.getBool(key) ?? false) return false;
    await prefs.setBool(key, true);
    return true;
  }

  Future<bool> isComplete(String subjectId, int unitIndex, int lessonIndex) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix${subjectId}_${unitIndex}_$lessonIndex') ?? false;
  }

  Future<int> completedCount(String subjectId, int totalUnits, int lessonsPerUnit) async {
    final prefs = await SharedPreferences.getInstance();
    int count = 0;
    for (int u = 0; u < totalUnits; u++) {
      for (int l = 0; l < lessonsPerUnit; l++) {
        if (prefs.getBool('$_prefix${subjectId}_${u}_$l') ?? false) count++;
      }
    }
    return count;
  }

  Future<Set<String>> completedSubjects(List<String> subjectIds, int totalLessons) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = <String>{};
    for (final sid in subjectIds) {
      int count = 0;
      for (int u = 0; u < 4; u++) {
        for (int l = 0; l < 5; l++) {
          if (prefs.getBool('$_prefix${sid}_${u}_$l') ?? false) count++;
        }
      }
      if (count >= totalLessons) completed.add(sid);
    }
    return completed;
  }
}

final lessonProgressProvider = Provider<LessonProgress>((ref) => LessonProgress());
