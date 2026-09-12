import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/sanitize_llm_response.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler((_) async => Directory.systemTemp.path);

  test('English chat: How can improve my performance?', () async {
    final info = await ModelManager().checkModel();
    expect(info.isReady && info.path != null, isTrue,
        reason: 'Qwen GGUF missing: ${info.status} ${info.path}');
    stdout.writeln('LOAD ${info.path}');

    final engine = LlamaCppEngineImpl(
      schedulerLane: EngineLane.reason,
      backendLabel: 'llama.cpp · Qwen 0.6B',
    );
    await engine.loadModel(info.path!);
    addTearDown(engine.dispose);

    final tutor = TutorPipeline(engine: engine);
    final sw = Stopwatch()..start();
    final reply = await tutor.respond(
      studentMessage: 'How can improve my performance ?',
      useCurriculum: false,
    );
    sw.stop();

    final cleaned = sanitizeLLMResponse(reply.text).trim();
    stdout.writeln('--- RAW ---');
    stdout.writeln(reply.text);
    stdout.writeln('--- CLEAN ---');
    stdout.writeln(cleaned);
    stdout.writeln('--- META stage=${reply.stage} ms=${sw.elapsedMilliseconds} ---');
    expect(cleaned, isNotEmpty);
    expect(cleaned.toLowerCase(), isNot(contains('<think>')));
    expect(
      cleaned.startsWith('I could not finish that answer'),
      isFalse,
      reason: 'tutor should produce a real answer, not the empty fallback',
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
