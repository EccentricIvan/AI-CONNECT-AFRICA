import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/ai_core/translate/supported_languages.dart';
import 'package:ai_connect_africa/l10n/app_locale.dart';
import 'package:ai_connect_africa/l10n/language_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Student _student({required String language}) {
  final now = DateTime(2026, 1, 1);
  return Student(
    id: 1,
    name: 'Amina',
    language: language,
    interestsJson: '[]',
    learningStyle: 'unknown',
    strengthsJson: '[]',
    weaknessesJson: '[]',
    goalsJson: '[]',
    streakDays: 0,
    totalPoints: 0,
    totalPracticeAttempted: 0,
    totalPracticeCorrect: 0,
    totalScenariosCompleted: 0,
    totalLessonsCompleted: 0,
    createdAt: now,
    lastActiveAt: now,
  );
}

ProviderContainer _containerFor(Student? student) {
  final container = ProviderContainer(
    overrides: [
      activeStudentProvider.overrideWith((ref) async => student),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('appLanguageProvider', () {
    test('falls back to English before the profile has loaded', () {
      final container = _containerFor(_student(language: 'sw'));

      // Read before awaiting the future: this is the frame app.dart renders
      // first, and it must not throw or block.
      expect(container.read(appLanguageProvider), 'en');
    });

    test('uses the saved profile language once loaded', () async {
      final container = _containerFor(_student(language: 'sw'));
      await container.read(activeStudentProvider.future);
      await container.read(persistedLanguageProvider.future);

      expect(container.read(appLanguageProvider), 'sw');
    });

    test('an explicit choice outranks the saved profile', () async {
      final container = _containerFor(_student(language: 'sw'));
      await container.read(activeStudentProvider.future);

      container.read(languageOverrideProvider.notifier).adoptSaved('lg');

      expect(container.read(appLanguageProvider), 'lg');
    });

    test('a guest with no profile can still pick a language', () async {
      final container = _containerFor(null);
      await container.read(activeStudentProvider.future);
      expect(container.read(appLanguageProvider), 'en');

      container.read(languageOverrideProvider.notifier).adoptSaved('yo');

      expect(container.read(appLanguageProvider), 'yo');
    });

    test('persisted language survives without a profile', () async {
      SharedPreferences.setMockInitialValues({
        kLearningLanguagePrefKey: 'sw',
      });
      final container = _containerFor(null);
      await container.read(persistedLanguageProvider.future);
      expect(container.read(appLanguageProvider), 'sw');
    });

    test('Kirundi is a first-class UI locale', () async {
      final container = _containerFor(null);
      await container.read(activeStudentProvider.future);
      container.read(languageOverrideProvider.notifier).adoptSaved('rn');
      expect(container.read(appLanguageProvider), 'rn');
      expect(languageName('rn'), 'Kirundi');
      expect(languagePromptName('rn'), 'Kinyarwanda');
      expect(hasUiString('rn', 'Learn'), isTrue);
    });

    test('clearing the choice hands control back to the profile', () async {
      final container = _containerFor(_student(language: 'sw'));
      await container.read(activeStudentProvider.future);
      container.read(languageOverrideProvider.notifier).adoptSaved('lg');

      container.read(languageOverrideProvider.notifier).clear();

      expect(container.read(appLanguageProvider), 'sw');
    });
  });
}
