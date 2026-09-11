import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';

class _ScriptedEngine extends InferenceEngine {
  _ScriptedEngine();
  final List<String> prompts = [];

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'Scripted';
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
    const text = 'Photosynthesis is how a plant makes food from sunlight.';
    await emitToken(onToken, text);
    return text;
  }

  @override
  Future<void> dispose() async {}
}

const _studentMessage = 'Nnyonnyola photosynthesis mu bumanyirivu';

void main() {
  group('chat round trip', () {
    test('Qwen reasons in English; student text is CURRENT', () async {
      final tutor = _ScriptedEngine();
      final pipeline = TutorPipeline(engine: tutor);
      final reply = await pipeline.respond(
        studentMessage: _studentMessage,
        languageCode: 'en',
        useCurriculum: true,
      );
      expect(tutor.prompts, isNotEmpty);
      expect(tutor.prompts.first, contains(_studentMessage));
      expect(tutor.prompts.first, contains('REPLY LANGUAGE: English'));
      expect(reply.text, contains('Photosynthesis'));
    });

    test('Learn section asks Qwen to use only the curriculum', () async {
      final tutor = _ScriptedEngine();
      final pipeline = TutorPipeline(engine: tutor);
      await pipeline.respond(
        studentMessage: 'What is photosynthesis?',
        languageCode: 'en',
        useCurriculum: true,
      );
      expect(tutor.prompts.first, contains('CURRICULUM:'));
    });

    test('Wholesome chat bypasses the curriculum vector lookup', () async {
      final tutor = _ScriptedEngine();
      final pipeline = TutorPipeline(engine: tutor);
      await pipeline.respond(
        studentMessage: 'Tell me a story about the stars',
        languageCode: 'en',
        useCurriculum: false,
      );
      expect(tutor.prompts.first, contains('CURRICULUM: bypassed'));
      expect(tutor.prompts.first, contains(kOpenWorldInstruction));
      expect(tutor.prompts.first, isNot(contains(kCurriculumOnlyInstruction)));
    });
  });
}
