import 'package:ai_connect_africa/features/app_dev_lab/app_build_intent.dart';
import 'package:ai_connect_africa/features/app_dev_lab/ui_schema_interpreter.dart';
import 'package:ai_connect_africa/shared/coding/interactive_html.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/preview_contract.dart';

void main() {
  test('stripMarkdownHtmlNoise removes fences and keeps document', () {
    const raw = '''
Here is your site:
```html
<!DOCTYPE html>
<html><body><h1>Hello</h1></body></html>
```
''';
    final cleaned = stripMarkdownHtmlNoise(raw);
    expect(cleaned, startsWith('<!DOCTYPE html>'));
    expect(cleaned, contains('<h1>Hello</h1>'));
    expect(cleaned, isNot(contains('```')));
  });

  test('htmlToBase64DataUri builds utf-8 base64 data URI', () {
    final uri = htmlToBase64DataUri(
      '<!DOCTYPE html><html><body><p>Café</p></body></html>',
    );
    expect(uri.scheme, 'data');
    expect(uri.data?.mimeType, 'text/html');
    expect(uri.data?.isBase64, isTrue);
    final decoded = uri.data!.contentAsString();
    expect(decoded, contains('Café'));
  });

  test('prepareHtmlForPreview shows a status page, not a sample site', () {
    final html = prepareHtmlForPreview('   ');
    expect(html, contains('Nothing to preview yet'));
    for (final invented in kInventedPreviewContent) {
      expect(html, isNot(contains(invented)));
    }
  });

  test('ensureRenderableHtmlDocument closes a truncated script', () {
    const partial = '''
<!DOCTYPE html><html><head><style>.a{color:red}</style></head>
<body><button id="x">Go</button>
<script>
document.getElementById("x").addEventListener("click", function(){
  console.log("hi"
''';
    final fixed = ensureRenderableHtmlDocument(partial);
    expect(fixed, contains('</script>'));
    expect(fixed, contains('</html>'));
    // Repaired, not replaced — the student's own button survives.
    expect(fixed, contains('<button id="x">Go</button>'));
  });

  test('ensureRenderableHtmlDocument leaves a complete static template as-is', () {
    // assets/templates/*.html are hand-authored static pages with no <script>
    // at all — these used to be swapped out for a generic tabs/checkout/quiz
    // demo shell, which destroyed the real design.
    const template = '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><style>:root{--ink:#10121a}</style></head>
<body>
<nav><a href="#why">Why switch</a></nav>
<h1>The productivity OS for modern teams</h1>
<a href="#contact" class="btn">Start Free</a>
</body>
</html>
''';
    final fixed = ensureRenderableHtmlDocument(template);
    expect(fixed.trim(), template.trim());
  });

  test('a dead onclick keeps the real page instead of a fabricated one', () {
    // The button does nothing because the student's script is missing. That is
    // truthful and teachable; inventing a working checkout calculator is not.
    const broken = '''
<!DOCTYPE html>
<html><head><style>.a{color:red}</style></head>
<body><h1>My shop</h1><button onclick="doThing()">Go</button></body></html>
''';
    final fixed = ensureRenderableHtmlDocument(broken);
    expect(fixed, contains('My shop'));
    expect(fixed, contains('onclick="doThing()"'));
    for (final invented in kInventedPreviewContent) {
      expect(fixed, isNot(contains(invented)));
    }
  });

  test('parseUiSchema maps Button/Alert/Cyberpunk lines', () {
    const raw = '''
```ui
OTIC_UI_V1
title: StudySpark
style: Neon Cyberpunk
---
Type: Header, Text: StudySpark
Type: Button, Text: Save, Action: Alert, Style: Cyberpunk
Type: List, Items: A|B|C
```
''';
    final doc = parseUiSchema(raw);
    expect(doc, isNotNull);
    expect(doc!.title, 'StudySpark');
    expect(doc.nodes.length, greaterThanOrEqualTo(2));
    final button = doc.nodes.firstWhere((n) => n.normalizedType == 'button');
    expect(button.text, 'Save');
    expect(button.action.toLowerCase(), contains('alert'));
    expect(button.style.toLowerCase(), contains('cyber'));
  });

  test('broken schema resolves to offline fallback template', () {
    final intent = AppBuildIntent(
      appTypeId: 'todo',
      appTypeName: 'Todo List',
      themeId: 'neon',
      themeName: 'Neon Cyberpunk',
      themePrimary: '#22D3EE',
      answers: const {'app_name': 'StudySpark', 'purpose': 'Save notes'},
      features: const ['Task list', 'Add task'],
    );
    final doc = resolveUiSchema('this is not a schema {{{', intent: intent);
    expect(doc.nodes, isNotEmpty);
    expect(doc.title, 'StudySpark');
  });

  test('fallbackUiSchemaSource is parseable', () {
    final intent = AppBuildIntent(
      appTypeId: 'todo',
      appTypeName: 'Todo List',
      themeId: 'obsidian',
      themeName: 'Deep Obsidian Dark',
      themePrimary: '#6366F1',
      answers: const {'app_name': 'MyApp'},
      features: const ['Task list'],
    );
    final source = fallbackUiSchemaSource(intent);
    expect(parseUiSchema(source), isNotNull);
  });
}
