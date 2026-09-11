import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AfriSLM GGUF loads', () async {
    final mgr = ModelManager();
    final info = await mgr.checkModel();
    if (!info.isReady || info.path == null) {
      stdout.writeln('SKIP: no AfriSLM GGUF on disk');
      return;
    }
    final engine = LlamaCppEngineImpl();
    await engine.loadModel(info.path!);
    final out = await engine.generate(
      prompt: 'Say hello in one word.',
      maxTokens: 8,
      temperature: 0,
    );
    stdout.writeln(out);
    expect(out.trim(), isNotEmpty);
    await engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
