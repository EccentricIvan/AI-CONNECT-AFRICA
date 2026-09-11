import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/curriculum/curriculum_provider.dart';
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

  test('curriculum questions through AfriSLM chat', () async {
    final info = await ModelManager().checkModel();
    if (!info.isReady || info.path == null) {
      stdout.writeln('SKIP: no AfriSLM GGUF');
      return;
    }
    final engine = LlamaCppEngineImpl();
    await engine.loadModel(info.path!);
    addTearDown(engine.dispose);

    final curriculum = CurriculumService();
    await curriculum.loadAll();

    final container = ProviderContainer(overrides: [
      activeStudentProvider.overrideWith((ref) async => null),
      languageOverrideProvider.overrideWith((ref) => 'en'),
      engineLoadedProvider.overrideWith((ref) async => engine),
      curriculumServiceProvider.overrideWithValue(curriculum),
      tutorPipelineProvider.overrideWith(
        (ref) async => TutorPipeline(engine: engine, curriculum: curriculum),
      ),
    ]);
    addTearDown(container.dispose);

    await container
        .read(chatProvider.notifier)
        .send('What is photosynthesis in green plants?');
    final state = container.read(chatProvider).valueOrNull;
    expect(state?.messages.length, greaterThanOrEqualTo(2));
    stdout.writeln(state?.messages.last.text);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
