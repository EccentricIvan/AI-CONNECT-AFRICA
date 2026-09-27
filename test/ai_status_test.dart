import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/ai_core/inference/mock_engine.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';

void main() {
  test('MockEngine is labeled as demo', () {
    final engine = MockEngine(demoReason: DemoReason.modelNotInstalled);
    expect(engine.isDemo, isTrue);
    expect(engine.backendLabel, 'Demo mode');
    expect(engine.demoReason.title, contains('Demo'));
  });

  test('AiStatus.fromEngine marks demo vs ready', () {
    final demo = AiStatus.fromEngine(
      MockEngine(demoReason: DemoReason.ollamaUnavailable),
    );
    expect(demo.isDemo, isTrue);
    // Plain words for the learner; engine names are never shown.
    expect(demo.title, contains('translation not ready'));
    expect(demo.title, isNot(contains('Ollama')));
  });
}
