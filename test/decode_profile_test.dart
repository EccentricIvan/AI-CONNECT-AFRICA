import 'package:ai_connect_africa/ai_core/inference/decode_profile.dart';
import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/services/qwen_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records whether each call arrived as prose, the way the real engines
/// read it — synchronously at the top of `generate`.
class _ProfileEngine extends InferenceEngine {
  final calls = <bool>[];

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'profile';
  @override
  Future<void> loadModel(String modelPath) async {}
  @override
  Future<void> dispose() async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    calls.add(isProseDecode);
    return 'ok';
  }
}

void main() {
  test('chat bubble answers decode as prose', () async {
    final engine = _ProfileEngine();
    final chat = QwenChatService(engine);
    await chat.generateAnswer(englishUser: 'What is matter?');
    await chat.streamAnswer(englishUser: 'And energy?').drain<void>();
    expect(engine.calls, [true, true]);
  });

  test('everything else keeps the exact greedy decode', () async {
    final engine = _ProfileEngine();
    await engine.generate(prompt: '<!DOCTYPE html>…');
    expect(engine.calls, [false]);
  });

  test('the flag survives awaits inside the prose zone', () async {
    final engine = _ProfileEngine();
    await runAsProse(() async {
      await Future<void>.delayed(Duration.zero);
      await engine.generate(prompt: 'x');
    });
    await engine.generate(prompt: 'y');
    expect(engine.calls, [true, false]);
  });
}
