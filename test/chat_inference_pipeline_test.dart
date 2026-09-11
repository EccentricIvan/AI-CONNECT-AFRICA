import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/stream_cascade.dart';
import 'package:ai_connect_africa/ai_core/science/science_text.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/services/afrislm_translation_service.dart';
import 'package:ai_connect_africa/services/chat_inference_pipeline.dart';
import 'package:ai_connect_africa/services/qwen_reasoning_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedEngine extends InferenceEngine {
  _ScriptedEngine(this.reply);
  final String reply;
  final prompts = <String>[];

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'scripted';
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
    await emitToken(onToken, reply);
    return reply;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('FormulaBypassTransformer skips H2O and equations', () async {
    final spans = await Stream<String>.fromIterable([
      'Water is H2O. ',
      r'Then $$4x-15=12x$$ holds.',
    ]).transform(const FormulaBypassTransformer()).toList();
    expect(spans.any((s) => s.bypassTranslation && s.text.contains('H2O')), isTrue);
    expect(
      spans.any((s) => s.bypassTranslation && s.text.contains('4x')),
      isTrue,
    );
  });

  test('English ingest starts Qwen on first sentence', () async {
    final buf = EnglishIngestBuffer();
    buf.add('Photosynthesis makes food.');
    final prompt = await buf.waitForReasoningPrompt();
    expect(prompt, contains('Photosynthesis'));
  });

  test('Qwen is the only engine that sees the English reasoning prompt',
      () async {
    final qwen = _ScriptedEngine('Chlorophyll absorbs sunlight.');
    final afrislm = _ScriptedEngine('should not be called in English');
    final pipeline = ChatInferencePipeline(
      reasoner: QwenReasoningService(qwen),
      tutor: TutorPipeline(engine: qwen),
      translator: AfriSlmTranslationService(null, engine: afrislm),
    );
    await pipeline.completeTurn(
      userText: 'What is chlorophyll?',
      languageCode: 'en',
    );
    expect(qwen.prompts, isNotEmpty);
    expect(afrislm.prompts, isEmpty);
  });

  test('cascade reasons in English and streams UI tokens', () async {
    final brain = _ScriptedEngine('Chlorophyll absorbs sunlight.');
    final pipeline = ChatInferencePipeline(
      reasoner: QwenReasoningService(brain),
      tutor: TutorPipeline(engine: brain),
      translator: AfriSlmTranslationService(null),
    );
    final shown = <String>[];
    final turn = await pipeline.completeTurn(
      userText: 'What is chlorophyll?',
      languageCode: 'en',
      onUiToken: shown.add,
    );
    expect(turn.englishUser, contains('chlorophyll'));
    expect(turn.displayText, contains('Chlorophyll'));
    expect(brain.prompts.single, contains('REPLY LANGUAGE: English'));
    expect(shown, isNotEmpty);
  });

  test('Python questions use the 1.5B programming brain', () async {
    final general = _ScriptedEngine('general photosynthesis');
    final coder = _ScriptedEngine('```python\nprint("hi")\n```');
    final pipeline = ChatInferencePipeline(
      reasoner: QwenReasoningService(general),
      tutor: TutorPipeline(engine: general),
      loadProgrammingEngine: () async => coder,
    );
    final turn = await pipeline.completeTurn(
      userText: 'Teach me a Python print statement',
      languageCode: 'en',
      useCurriculum: false,
    );
    expect(coder.prompts, isNotEmpty);
    expect(general.prompts, isEmpty);
    expect(turn.displayText, contains('print'));
  });

  test('isMathPassThrough matches the requested formula examples', () {
    expect(isMathPassThrough('H2O'), isTrue);
    expect(isMathPassThrough('CO2'), isTrue);
    expect(isMathPassThrough('4x/3-5=6+4x'), isTrue);
    expect(isMathPassThrough(r'$x^2$'), isTrue);
  });
}
