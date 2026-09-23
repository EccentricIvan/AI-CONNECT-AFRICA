import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/language_provider.dart';
import '../teacher/teacher_pin.dart';

/// Hands a shared device from one learner to another.
///
/// Switching is a privacy boundary, not just a UI change: the tutor's
/// in-memory conversation and the engine's KV cache still hold the previous
/// learner's chat, and must be dropped before the next learner types anything
/// — otherwise the tutor answers learner B with learner A's context.
class LearnerSwitcher {
  LearnerSwitcher(this._ref);

  final Ref _ref;

  Future<void> switchTo(int studentId) async {
    final db = _ref.read(dbProvider);
    final student = await db.studentDao.getStudentById(studentId);
    if (student == null) return;

    // Drop the previous learner's thread, tutor memory and engine session
    // first, before anything can observe the new learner.
    _ref.read(chatProvider.notifier).reset();
    // The device is being handed to a learner: the teacher area locks again.
    _ref.read(teacherUnlockedProvider.notifier).state = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kActiveStudentIdKey, student.id);
    // The router treats this key as "onboarding done"; keep it the name of
    // whoever is actually using the device.
    await prefs.setString('student_name', student.name);
    await db.studentDao.touchStudent(student.id);

    // Language is device-wide state; take the new learner's.
    _ref.read(languageOverrideProvider.notifier).clear();
    await persistLearningLanguage(student.language);
    _ref.invalidate(persistedLanguageProvider);

    _ref.invalidate(activeStudentProvider);
    _ref.invalidate(hasProfileProvider);
    _ref.invalidate(studentNotifierProvider);
    debugPrint('Switched learner to #${student.id}');
  }
}

final learnerSwitcherProvider = Provider((ref) => LearnerSwitcher(ref));
