import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/localized_generate.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';

class _Brain extends InferenceEngine {
  _Brain(this.reply);
  final String reply;
  String? lastSystem;

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'Brain';
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
    lastSystem = systemPrompt;
    await emitToken(onToken, reply);
    return reply;
  }

  @override
  Future<void> dispose() async {}
}

class _StreamingBrain extends InferenceEngine {
  _StreamingBrain(this.tokens);
  final List<String> tokens;

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'Brain';
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
    for (final token in tokens) {
      await emitToken(onToken, token);
    }
    return tokens.join();
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('English sessions stream the brain reply as-is', () async {
    final out = await generateLocalizedReply(
      engine: _Brain('Hello student.'),
      prompt: 'Hi',
      languageCode: 'en',
    );
    expect(out.text, 'Hello student.');
    expect(out.translatedLanguage, isNull);
  });

  test('local-language sessions reason in English without a translator', () async {
    final brain = _Brain('Photosynthesis makes food from sunlight.');
    final out = await generateLocalizedReply(
      engine: brain,
      prompt: 'Explain photosynthesis',
      languageCode: 'rw',
    );
    expect(out.text, contains('Photosynthesis'));
    expect(out.translatedLanguage, 'rw');
    expect(brain.lastSystem, contains(kTutorContract.split('\n').first));
  });

  test('streamed tokens close leaked math delimiters', () async {
    final shown = <String>[];
    final out = await generateLocalizedReply(
      engine: _StreamingBrain([r'$$ 4x - 15']),
      prompt: 'math',
      languageCode: 'rw',
      onDisplay: shown.add,
    );
    expect(out.text.trim().endsWith(r'$$'), isTrue);
    expect(shown.last.trim().endsWith(r'$$'), isTrue);
  });
}
