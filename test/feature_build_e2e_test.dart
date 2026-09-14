import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_build_coder.dart';
import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pipeline e2e (no GGUF): feature intent → coder generate → extractable HTML.
class _BuildEngine extends InferenceEngine {
  _BuildEngine(this._replies);
  final List<String> _replies;
  final prompts = <String>[];
  var _i = 0;

  @override
  bool get isReady => true;

  @override
  String get backendLabel => 'scripted-build';

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
    final reply = _replies[_i.clamp(0, _replies.length - 1)];
    _i++;
    await emitToken(onToken, reply);
    return reply;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('e2e feature selection builds a website then an app', () async {
    const siteReply = '''
<!DOCTYPE html>
<html><head><title>Kampala Crust Bakery</title></head>
<body>
  <h1>Kampala Crust Bakery</h1>
  <p>Fresh bread every morning</p>
  <p>+256 700 111 222</p>
</body></html>
''';
    const appReply = '''
```html
<!DOCTYPE html>
<html><body>
  <div class="app"><h1>BrainBoost Quiz</h1>
  <section>Question screen</section>
  <section>Score tracker</section>
  </div>
</body></html>
```
''';

    final engine = _BuildEngine([siteReply, appReply]);

    final siteIntent = SiteBuildIntent(
      templateId: 'bakery',
      templateName: 'Bakery / Restaurant',
      themeName: 'Ocean Blue',
      themePrimary: '#2563eb',
      answers: {
        'business_name': 'Kampala Crust Bakery',
        'phone': '+256 700 111 222',
        'address': 'Plot 9, Kampala Road',
      },
      content: {'tagline': 'Fresh bread every morning'},
    );
    final siteHtml = await generateSiteHtmlWithCoder(
      engine: engine,
      intent: siteIntent,
    );
    expect(engine.prompts[0], contains('Kampala Crust Bakery'));
    expect(siteHtml, isNotNull);
    expect(siteHtml!, contains('Kampala Crust Bakery'));
    expect(siteHtml, contains('<!DOCTYPE html>'));

    final appIntent = AppBuildIntent(
      appTypeId: 'quiz',
      appTypeName: 'Quiz Game',
      themeId: '3',
      themeName: 'Royal Purple',
      themePrimary: '#7c3aed',
      answers: {
        'app_name': 'BrainBoost Quiz',
        'purpose': 'Practice math before exams',
      },
      features: ['Question screen', 'Score tracker'],
    );
    final appHtml = await generateAppHtmlWithCoder(
      engine: engine,
      intent: appIntent,
    );
    expect(engine.prompts[1], contains('BrainBoost Quiz'));
    expect(engine.prompts[1], contains('Question screen'));
    expect(appHtml, isNotNull);
    expect(appHtml!, contains('BrainBoost Quiz'));
    expect(appHtml, contains('Score tracker'));

    // Incomplete coder output → app still builds via fallback.
    final emptyEngine = _BuildEngine(['Sorry, I cannot help.']);
    final fallback = await generateAppHtmlWithCoder(
      engine: emptyEngine,
      intent: appIntent,
    );
    expect(fallback, isNotNull);
    expect(fallback!, contains('<!DOCTYPE html>'));
    expect(fallback, contains('Sorry, I cannot help.'));
    expect(fallback, contains('OTIC_INTERACTIVE_RUNTIME'));
  });
}
