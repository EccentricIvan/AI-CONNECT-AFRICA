import 'package:ai_connect_africa/ai_core/inference/mock_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/ai_core/translate/chat_languages.dart';
import 'package:ai_connect_africa/core/app_info_provider.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/certificates/certificates_screen.dart';
import 'package:ai_connect_africa/features/create/create_screen.dart';
import 'package:ai_connect_africa/features/learn/learn_screen.dart';
import 'package:ai_connect_africa/features/learn/path/path_provider.dart';
import 'package:ai_connect_africa/features/onboarding/onboarding_screen.dart';
import 'package:ai_connect_africa/features/practice/practice_screen.dart';
import 'package:ai_connect_africa/features/settings/settings_screen.dart';
import 'package:ai_connect_africa/l10n/app_locale.dart';
import 'package:ai_connect_africa/l10n/language_provider.dart';
import 'package:ai_connect_africa/voice/voice_provider.dart';
import 'package:ai_connect_africa/voice/voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chrome that must exist in every chat language across Home (AI chat),
/// Practice, Create, Settings, Certificates, and Onboarding.
const _appChromeKeys = [
  'Learn',
  'Practice',
  'Apply',
  'Create',
  'Settings',
  'Certificates',
  'Ask AI anything...',
  'Send',
  'Offline mode',
  'Learning language',
  'Sharpen your skills',
  'Turn ideas into projects',
  'Profile, AI model & preferences',
  'Celebrate completed paths',
  'Welcome to AI Connect Africa',
  'Start learning',
  'Next',
  'Ask anything, learn together',
  'Get instant help',
  'Share your knowledge',
  'Explore your courses',
  'Use AI to answer this question',
];

class _SilentVoice extends VoiceService {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String languageCode = 'en'}) async {}

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    String localeId = '',
  }) async =>
      false;
}

List<Override> _overrides() => [
      activeStudentProvider.overrideWith((ref) async => null),
      studentPathsProvider.overrideWith((ref) async => []),
      voiceServiceProvider.overrideWithValue(_SilentVoice()),
      engineLoadedProvider.overrideWith(
        (ref) async => MockEngine(demoReason: DemoReason.modelNotInstalled),
      ),
      modelInfoProvider.overrideWith(
        (ref) async => const ModelInfo(status: ModelStatus.notInstalled),
      ),
      translateModelInfoProvider.overrideWith(
        (ref) async => const ModelInfo(status: ModelStatus.notInstalled),
      ),
      programmingModelInfoProvider.overrideWith(
        (ref) async => const ModelInfo(status: ModelStatus.notInstalled),
      ),
      packageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'AI Connect Africa',
          packageName: 'africa.aiconnect',
          version: '0.0.0',
          buildNumber: '0',
        ),
      ),
    ];

Future<BuildContext> _pump(
  WidgetTester tester, {
  required String languageCode,
  required Widget child,
}) async {
  final container = ProviderContainer(overrides: _overrides());
  addTearDown(container.dispose);
  container.read(languageOverrideProvider.notifier).adoptSaved(languageCode);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        key: ValueKey('app-$languageCode-${child.runtimeType}'),
        home: AppLocale(
          key: const ValueKey('locale-root'),
          languageCode: languageCode,
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tester.element(find.byKey(const ValueKey('locale-root')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final languages = [...kPrimaryChatLanguages.where((c) => c != 'en'), 'rn'];

  test('UI tables cover app chrome for every chat language', () {
    for (final code in languages) {
      for (final key in _appChromeKeys) {
        expect(
          hasUiString(code, key),
          isTrue,
          reason: '$code missing chrome "$key"',
        );
        expect(
          uiString(code, key),
          isNotEmpty,
          reason: '$code empty chrome "$key"',
        );
      }
    }
  });

  testWidgets('Home, Learn, Practice, Create, Settings, Certs, Onboarding follow each language',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final code in languages) {
      Future<void> expectChrome(String key) async {
        final ctx = tester.element(find.byKey(const ValueKey('locale-root')));
        expect(
          find.text(tr(ctx, key)),
          findsWidgets,
          reason: '$code: "$key" not on screen',
        );
      }

      await _pump(tester, languageCode: code, child: const LearnScreen());
      await expectChrome('How can I help you today?');
      await expectChrome('Ask anything...');

      await _pump(tester, languageCode: code, child: const PracticeScreen());
      await expectChrome('Practice');
      await expectChrome('Apply');
      await expectChrome('Sharpen your skills');

      await _pump(tester, languageCode: code, child: const CreateScreen());
      await expectChrome('Create');

      await _pump(tester, languageCode: code, child: const SettingsScreen());
      await expectChrome('Settings');
      await expectChrome('Learning language');

      await _pump(
        tester,
        languageCode: code,
        child: const CertificatesScreen(),
      );
      await expectChrome('Certificates');

      await _pump(tester, languageCode: code, child: const OnboardingScreen());
      await expectChrome('Welcome to AI Connect Africa');
      await expectChrome('Start learning');
    }
  });
}
