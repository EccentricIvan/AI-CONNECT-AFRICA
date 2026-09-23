import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';

class _CountingEngine extends InferenceEngine {
  int disposals = 0;
  final prompts = <String>[];

  @override
  bool get isReady => true;

  @override
  String get backendLabel => 'test brain';

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    prompts.add(prompt);
    return '<html></html>';
  }

  @override
  Future<void> dispose() async => disposals++;
}

void main() {
  test('programming work runs on the one brain', () async {
    final brain = _CountingEngine();
    final runtime = DualModelRuntime(reasoner: brain);

    expect(identical(runtime.programming, brain), isTrue);
    expect(identical(await runtime.ensureProgramming(), brain), isTrue);
    expect(identical(runtime.coderService.engine, brain), isTrue);
    expect(identical(runtime.coderService, runtime.coderService), isTrue,
        reason: 'one wrapper, not a new one per call');
  });

  test('a build uses the brain and never disposes it', () async {
    final brain = _CountingEngine();
    final coder = DualModelRuntime(reasoner: brain).coderService;

    await coder.generate(prompt: 'Build a page');
    await coder.dispose();

    expect(brain.prompts, ['Build a page']);
    expect(brain.disposals, 0,
        reason: 'the tutor answers on this engine next');
  });
}
