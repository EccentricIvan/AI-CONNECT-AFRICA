import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai_core/translate/supported_languages.dart';
import '../db/providers/db_provider.dart';

/// Survives app restart on Android and Windows even before a student row
/// exists — otherwise the first Learn turn after Install Packages is English.
const kLearningLanguagePrefKey = 'otic_learning_language';

Future<void> persistLearningLanguage(String code) async {
  if (!isSupportedLearningLanguage(code)) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLearningLanguagePrefKey, code);
  } catch (e) {
    debugPrint('persistLearningLanguage failed: $e');
  }
}

Future<String?> readPersistedLearningLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(kLearningLanguagePrefKey);
    if (code == null || code.isEmpty) return null;
    if (!isSupportedLearningLanguage(code)) return null;
    return code;
  } catch (e) {
    debugPrint('readPersistedLearningLanguage failed: $e');
    return null;
  }
}

final persistedLanguageProvider = FutureProvider<String?>((ref) async {
  return readPersistedLearningLanguage();
});

/// Single source of truth for "what language is this app speaking right now".
///
/// Both halves of the dual-model setup hang off this one value:
///
///   * static UI labels  → [AppLocale] / `tr()`, table lookups, instant
///   * dynamic chat text → AfriSLM round-trip around the Qwen3-0.6B tutor
///
/// Before this, each half resolved the language independently from
/// [activeStudentProvider] — the UI in `app.dart` and the engine in
/// `studentLanguageCode`. They agreed in the steady state, but there was no
/// way to change the language *without* writing a student row (so guests had
/// no language at all), and a single chat turn re-derived the code up to four
/// times, which a mid-turn switch could tear across.
///
/// Deliberately stores only the *explicit* choice, never a copy of the
/// student's saved language. [StudentNotifier.updateProfile] invalidates
/// [activeStudentProvider] on every profile edit, so a notifier that seeded
/// itself from the DB would push the stored value back over an unsaved guest
/// choice whenever an unrelated field (name, age, interests) was touched.
class LanguageOverride extends Notifier<String?> {
  /// Null means "nothing chosen this session" — fall through to prefs / profile.
  @override
  String? build() => null;

  /// Flips the whole app — labels and model routing — to [code].
  ///
  /// Applies to the UI synchronously, writes SharedPreferences so a downloaded
  /// APK / Windows zip keeps the language after restart, then persists to the
  /// student profile when one exists.
  Future<void> setLanguage(String code) async {
    state = code;
    await persistLearningLanguage(code);
    ref.invalidate(persistedLanguageProvider);
    try {
      final student = await ref.read(activeStudentProvider.future);
      if (student == null) return;
      await ref.read(studentNotifierProvider.notifier).updateProfile(
            id: student.id,
            name: student.name,
            language: code,
          );
    } catch (e) {
      debugPrint('setLanguage: could not persist language "$code": $e');
    }
  }

  /// Aligns the session choice with a language just written to a profile.
  ///
  /// Onboarding writes `language` straight through [StudentNotifier], so
  /// without this a guest who picked Swahili in Settings and then onboarded in
  /// Yoruba would keep getting Swahili — the override would outrank the
  /// profile it was meant to defer to.
  void adoptSaved(String code) => state = code;

  /// Drops back to whatever prefs / the profile says (used when switching profiles).
  void clear() => state = null;
}

final languageOverrideProvider =
    NotifierProvider<LanguageOverride, String?>(LanguageOverride.new);

/// The resolved language code for **UI rendering**: explicit choice, else
/// the saved profile, else the on-disk preference, else English.
///
/// Synchronous on purpose — a widget cannot await, and rendering English for
/// the frame or two before prefs/profile load is harmless. The engine side
/// must *not* use this: see [studentLanguageCode], which awaits prefs and
/// the profile so the first message of a session is routed correctly.
final appLanguageProvider = Provider<String>((ref) {
  return resolveLearningLanguage(
    override: ref.watch(languageOverrideProvider),
    persisted: ref.watch(persistedLanguageProvider).valueOrNull,
    studentLanguage: ref.watch(activeStudentProvider).valueOrNull?.language,
  );
});
