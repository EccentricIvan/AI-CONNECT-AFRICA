import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/runtime_config.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler(
          (MethodCall call) async => Directory.systemTemp.path);

  test('AfriSLM tutor latency', () async {
    final info = await ModelManager().checkModel();
    if (!info.isReady || info.path == null) {
      stdout.writeln('SKIP: no AfriSLM GGUF');
      return;
    }
    final engine = LlamaCppEngineImpl();
    await engine.loadModel(info.path!);
    final sw = Stopwatch()..start();
    DateTime? first;
    await engine.generate(
      prompt: 'CURRENT: What is photosynthesis?\nTutor:',
      systemPrompt: kTutorContract,
      maxTokens: kMaxNewTokens,
      temperature: kTutorTemperature,
      onToken: (_) => first ??= DateTime.now(),
    );
    stdout.writeln(
      'total=${sw.elapsedMilliseconds}ms first=${first == null ? -1 : first!.difference(DateTime.now().subtract(sw.elapsed)).inMilliseconds}',
    );
    await engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
