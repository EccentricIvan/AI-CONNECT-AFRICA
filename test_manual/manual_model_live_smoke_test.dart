import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/model/programming_model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live GGUF smoke. Run ONE test per process — loading a second llama.cpp
/// model in the same isolate has crashed this machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler((_) async => Directory.systemTemp.path);

  test('discover all three GGUFs', () async {
    final qwen = await ModelManager().checkModel();
    final afri = await AfriSlmModelManager().checkModel();
    final coder = await ProgrammingModelManager().checkModel();
    stdout.writeln('QWEN ${qwen.status} ${qwen.path} ${qwen.sizeBytes}');
    stdout.writeln('AFRI ${afri.status} ${afri.path} ${afri.sizeBytes}');
    stdout.writeln('CODER ${coder.status} ${coder.path} ${coder.sizeBytes}');
    expect(qwen.isReady, isTrue);
    expect(afri.isReady, isTrue);
    expect(coder.isReady, isTrue);
    expect(qwen.path!.toLowerCase().contains('afrislm'), isFalse);
  });

  test('qwen 0.6B generates English', () async {
    final info = await ModelManager().checkModel();
    expect(info.isReady && info.path != null, isTrue);
    stdout.writeln('LOAD ${info.path}');
    final engine = LlamaCppEngineImpl(
      schedulerLane: EngineLane.reason,
      backendLabel: 'llama.cpp · Qwen 0.6B',
    );
    await engine.loadModel(info.path!);
    addTearDown(engine.dispose);
    final reply = await engine.generate(
      prompt: 'What is 2 plus 2? Reply in one short sentence.',
      systemPrompt: 'You are a brief tutor. Answer in one sentence.',
      maxTokens: 40,
      temperature: 0.1,
    );
    stdout.writeln('QWEN REPLY: $reply');
    expect(reply.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('AfriSLM translates English to Swahili', () async {
    final info = await AfriSlmModelManager().checkModel();
    expect(info.isReady && info.path != null, isTrue);
    stdout.writeln('LOAD ${info.path}');
    final engine = LlamaCppEngineImpl(
      schedulerLane: EngineLane.translate,
      backendLabel: 'llama.cpp · AfriSLM 0.8B',
    );
    await engine.loadModel(info.path!);
    addTearDown(engine.dispose);
    final reply = await engine.generate(
      prompt: 'English: The plant needs sunlight.\nSwahili:',
      systemPrompt: 'Translate English to Swahili. Output only the translation.',
      maxTokens: 40,
      temperature: 0.1,
    );
    stdout.writeln('AFRI REPLY: $reply');
    expect(reply.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('coder 1.5B writes a tiny Python function', () async {
    final info = await ProgrammingModelManager().checkModel();
    expect(info.isReady && info.path != null, isTrue);
    stdout.writeln('LOAD ${info.path}');
    final engine = LlamaCppEngineImpl(
      schedulerLane: EngineLane.program,
      backendLabel: 'llama.cpp · Qwen 1.5B Coder',
    );
    await engine.loadModel(info.path!);
    addTearDown(engine.dispose);
    final reply = await engine.generate(
      prompt: 'Write a Python function add(a, b) that returns a + b. Code only.',
      systemPrompt: 'You are a coding tutor. Reply with a short fenced snippet.',
      maxTokens: 80,
      temperature: 0.1,
    );
    stdout.writeln('CODER REPLY: $reply');
    expect(reply.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
