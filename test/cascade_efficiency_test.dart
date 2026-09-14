import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Brain extends InferenceEngine {
  int calls = 0;
  String? lastPrompt;

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'Count';
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
    calls++;
    lastPrompt = prompt;
    const out = 'ok';
    onToken?.call(out);
    return out;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('Learn: one Qwen generate, curriculum-only instruction', () async {
    final brain = _Brain();
    final pipeline = TutorPipeline(engine: brain);
    await pipeline.respond(
      studentMessage: 'What is photosynthesis in green plants?',
      languageCode: 'en',
      useCurriculum: true,
    );
    expect(brain.calls, 1);
    expect(brain.lastPrompt, contains('What is photosynthesis'));
    expect(brain.lastPrompt, contains('REPLY: English'));
  });

  test('Wholesome: one Qwen generate, curriculum bypassed', () async {
    final brain = _Brain();
    final pipeline = TutorPipeline(engine: brain);
    await pipeline.respond(
      studentMessage: 'How are you today?',
      languageCode: 'en',
      useCurriculum: false,
    );
    expect(brain.calls, 1);
    expect(brain.lastPrompt, contains(kOpenWorldInstruction));
  });
}
