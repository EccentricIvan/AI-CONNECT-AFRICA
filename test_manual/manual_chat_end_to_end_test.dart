import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/l10n/language_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler(
          (MethodCall call) async => Directory.systemTemp.path);

  test('chat replies in en, lg, rw through ChatNotifier (AfriSLM)', () async {
    final info = await ModelManager().checkModel();
    if (!info.isReady || info.path == null) {
      stdout.writeln('SKIP: no AfriSLM GGUF');
      return;
    }
    final engine = LlamaCppEngineImpl();
    await engine.loadModel(info.path!);
    addTearDown(engine.dispose);

    for (final lang in ['en', 'lg', 'rw']) {
      final container = ProviderContainer(overrides: [
        activeStudentProvider.overrideWith((ref) async => null),
        languageOverrideProvider.overrideWith((ref) => lang),
        engineLoadedProvider.overrideWith((ref) async => engine),
        tutorPipelineProvider.overrideWith(
          (ref) async => TutorPipeline(engine: engine),
        ),
      ]);
      addTearDown(container.dispose);
      await container.read(chatProvider.notifier).send(
            lang == 'rw'
                ? 'Shaka agaciro ka x: 2x + 3 = 11'
                : 'What is photosynthesis?',
          );
      final state = container.read(chatProvider).valueOrNull;
      stdout.writeln('$lang → ${state?.messages.last.text}');
      expect(state?.messages.length, greaterThanOrEqualTo(2));
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
