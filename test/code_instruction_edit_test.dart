import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/shared/coding/code_autocorrect.dart'
    show CodeAutocorrectKind;
import 'package:ai_connect_africa/shared/coding/code_instruction_edit.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedEngine extends InferenceEngine {
  _ScriptedEngine(this.reply, {this.ready = true});
  final String reply;
  final bool ready;
  final prompts = <String>[];
  String? lastSystem;

  @override
  bool get isReady => ready;

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

const _page = '''
<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: sans-serif; }
header, nav { background: #451a03; }
.btn { background: #a16207; }
</style>
</head>
<body><header><h1>Sweet Treats</h1></header></body>
</html>
''';

void main() {
  group('applyCodeInstruction', () {
    test('appends the model CSS as an override and keeps the markup intact',
        () async {
      final engine = _ScriptedEngine('h1 { text-align: center !important; }');

      final result = await applyCodeInstruction(
        source: _page,
        instruction: 'center the heading',
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );

      expect(result, isNotNull);
      expect(result, contains('text-align: center !important'));
      // Original content and its styles survive untouched.
      expect(result, contains('Sweet Treats'));
      expect(result, contains('background: #a16207'));
      // Override lands inside <head> so it wins on source order.
      expect(
        result!.indexOf('/* AI change */'),
        lessThan(result.indexOf('</head>')),
      );
    });

    test('sends the instruction and real page selectors, never the document',
        () async {
      final engine = _ScriptedEngine('.btn { background: blue !important; }');

      await applyCodeInstruction(
        source: _page,
        instruction: 'make the buttons blue',
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );

      final prompt = engine.prompts.single;
      expect(prompt, contains('make the buttons blue'));
      expect(prompt, contains('.btn'));
      expect(prompt, contains('header'));
      // The page body must never be shipped to the model — that is what made
      // whole-document rewrites truncate against the small token ceiling.
      expect(prompt, isNot(contains('Sweet Treats')));
      expect(prompt, isNot(contains('<!DOCTYPE')));
      expect(engine.lastSystem, contains('CSS'));
    });

    test('returns null when the engine is not ready', () async {
      final engine = _ScriptedEngine('h1 { color: red; }', ready: false);
      final result = await applyCodeInstruction(
        source: _page,
        instruction: 'center the heading',
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      expect(result, isNull);
      expect(engine.prompts, isEmpty);
    });

    test('returns null for a blank instruction without calling the engine',
        () async {
      final engine = _ScriptedEngine('h1 { color: red; }');
      final result = await applyCodeInstruction(
        source: _page,
        instruction: '   ',
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      expect(result, isNull);
      expect(engine.prompts, isEmpty);
    });

    test('rejects prose replies that contain no CSS rules', () async {
      final engine = _ScriptedEngine("I can't do that, sorry.");
      final result = await applyCodeInstruction(
        source: _page,
        instruction: 'change the phone number to 0700',
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      expect(result, isNull);
    });

    test('rejects a whole document reply rather than nesting it in the page',
        () async {
      final engine = _ScriptedEngine(
        '<!DOCTYPE html><html><body><p>oops { }</p></body></html>',
      );
      final result = await applyCodeInstruction(
        source: _page,
        instruction: 'center the heading',
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      expect(result, isNull);
    });
  });

  group('extractCssRules', () {
    test('strips css fences and style wrappers', () {
      expect(
        extractCssRules('```css\nh1 { color: red; }\n```'),
        'h1 { color: red; }',
      );
      expect(
        extractCssRules('<style>h1 { color: red; }</style>'),
        'h1 { color: red; }',
      );
    });
  });

  group('existingStyleSelectors', () {
    test('lists page selectors and skips at-rules and :root', () {
      final selectors = existingStyleSelectors(_page);
      expect(selectors, containsAll(<String>['body', 'header', 'nav', '.btn']));
    });

    test('caps the list so prompt size never tracks page size', () {
      final many = StringBuffer('<style>');
      for (var i = 0; i < 100; i++) {
        many.write('.c$i { color: red; }');
      }
      many.write('</style>');
      expect(existingStyleSelectors(many.toString()), hasLength(30));
    });
  });
}
