import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
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

  test('Swahili student message goes natively through AfriSLM', () async {
    final info = await ModelManager().checkModel();
    if (!info.isReady || info.path == null) {
      stdout.writeln('SKIP: no AfriSLM GGUF');
      return;
    }
    final engine = LlamaCppEngineImpl();
    await engine.loadModel(info.path!);
    const swahili = 'Habari, naweza kujifunza photosynthesis?';
    final reply = await engine.generate(
      prompt: 'Student: $swahili\nTutor:',
      systemPrompt: 'Reply in Swahili in 2 short sentences.',
      maxTokens: 80,
      temperature: 0.2,
    );
    stdout.writeln(reply);
    expect(reply.trim(), isNotEmpty);
    await engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
