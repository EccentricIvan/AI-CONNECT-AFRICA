import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_build_coder.dart';
import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedEngine extends InferenceEngine {
  _ScriptedEngine(this.reply);
  final String reply;
  final prompts = <String>[];
  String? lastSystem;

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
    lastSystem = systemPrompt;
    await emitToken(onToken, reply);
    return reply;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  const sampleHtml =
      '<!DOCTYPE html><html><body><h1>Built</h1></body></html>';

  test('site coder receives recorded features and returns HTML', () async {
    final engine = _ScriptedEngine(sampleHtml);
    final intent = SiteBuildIntent(
      templateId: 'bakery',
      templateName: 'Bakery / Restaurant',
      themeName: 'Ocean Blue',
      themePrimary: '#2563eb',
      answers: {'business_name': 'Sweet Treats'},
      content: {'tagline': 'Fresh daily'},
    );

    final html = await generateSiteHtmlWithCoder(
      engine: engine,
      intent: intent,
    );

    expect(engine.prompts, hasLength(1));
    expect(engine.prompts.single, contains('Sweet Treats'));
    expect(engine.prompts.single, contains('Fresh daily'));
    expect(engine.lastSystem, contains('websites'));
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('Built'));
  });

  test('app coder receives selected features and returns HTML', () async {
    final engine = _ScriptedEngine('''
```html
<!DOCTYPE html>
<html><body><div class="app">Quiz</div></body></html>
```
''');
    final intent = AppBuildIntent(
      appTypeId: 'quiz',
      appTypeName: 'Quiz Game',
      themeId: '3',
      themeName: 'Royal Purple',
      themePrimary: '#7c3aed',
      answers: {
        'app_name': 'BrainBoost',
        'purpose': 'Practice math before exams',
      },
      features: ['Question screen', 'Score tracker'],
    );

    final html = await generateAppHtmlWithCoder(
      engine: engine,
      intent: intent,
    );

    expect(engine.prompts.single, contains('BrainBoost'));
    expect(engine.prompts.single, contains('Question screen'));
    expect(engine.prompts.single, contains('Score tracker'));
    expect(engine.lastSystem, contains('mobile-web'));
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('Quiz'));
  });

  test('app fallback shell includes recorded features', () {
    final intent = AppBuildIntent(
      appTypeId: 'todo',
      appTypeName: 'To-Do List',
      themeId: '2',
      themeName: 'Forest Green',
      themePrimary: '#059669',
      answers: {'app_name': 'TaskTiny', 'purpose': 'Daily school tasks'},
      features: ['Task list', 'Mark done'],
    );
    final html = fallbackAppHtml(intent);
    expect(html, contains('TaskTiny'));
    expect(html, contains('Task list'));
    expect(html, contains('Mark done'));
    expect(html, contains('#059669'));
  });
}
