import 'package:ai_connect_africa/features/app_dev_lab/app_build_intent.dart';
import 'package:ai_connect_africa/features/app_dev_lab/ui_schema_interpreter.dart';
import 'package:ai_connect_africa/shared/coding/interactive_html.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('prepareHtmlForPreview falls back when empty', () {
    final html = prepareHtmlForPreview('   ');
    expect(html, contains('OTIC_INTERACTIVE_RUNTIME'));
    expect(html, contains('<script'));
  });

  test('ensureInteractiveHtmlDocument repairs truncated script', () {
    const partial = '''
<!DOCTYPE html><html><head><style>.a{color:red}</style></head>
<body><button id="x">Go</button>
<script>
document.getElementById("x").addEventListener("click", function(){
  console.log("hi"
''';
    final fixed = ensureInteractiveHtmlDocument(partial);
    expect(fixed, contains('OTIC_INTERACTIVE_RUNTIME'));
    expect(fixed, contains('</script>'));
    expect(htmlLooksInteractive(fixed), isTrue);
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
