import 'dart:io';

import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/preview_contract.dart';

/// The preview contract: what the pane paints is the code in the editor —
/// repaired for structure if it has to be, never added to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Text a reader would see on the rendered page — `<head>` (title, CSS) and
  /// scripts removed, then tags stripped.
  String visibleText(String html) => html
      .replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  group('preview output is strictly the editor content', () {
    test('a complete document round-trips unchanged', () {
      const code = '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Mary's Bakery</title>
<style>body{background:#fffaf0}h1{color:#b45309}</style></head>
<body><h1>Mary's Bakery</h1><p>Fresh bread daily in Kampala.</p></body>
</html>
''';
      expect(prepareHtmlForPreview(code).trim(), code.trim());
    });

    test('nothing is rendered that the student did not write', () {
      const code = '<!DOCTYPE html><html><body><h1>Just this</h1></body></html>';
      final rendered = visibleText(prepareHtmlForPreview(code));
      expect(rendered, 'Just this');
    });

    test('every template in assets/templates survives untouched', () async {
      final files = Directory('assets/templates')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.html'));
      expect(files, isNotEmpty);

      for (final file in files) {
        final source = await file.readAsString();
        final prepared = prepareHtmlForPreview(source);
        expect(
          prepared.trim(),
          source.trim(),
          reason: '${file.path} was altered on the way to the preview',
        );
        for (final invented in kInventedPreviewContent) {
          expect(
            prepared,
            isNot(contains(invented)),
            reason: '${file.path} picked up invented content: $invented',
          );
        }
      }
    });

    test('a page with no JavaScript stays a page with no JavaScript', () {
      const staticPage = '''
<!DOCTYPE html>
<html><head><style>h1{color:navy}</style></head>
<body><h1>Static by choice</h1></body></html>
''';
      final prepared = prepareHtmlForPreview(staticPage);
      expect(prepared, isNot(contains('<script')));
      expect(visibleText(prepared), 'Static by choice');
    });

    test('a bare fragment is wrapped, not decorated', () {
      final prepared = prepareHtmlForPreview('<h1>Fragment</h1>');
      expect(prepared, contains('<!DOCTYPE html>'));
      expect(prepared, contains('<h1>Fragment</h1>'));
      expect(visibleText(prepared), 'Fragment');
    });
  });

  group('LiveHtmlStudio mirrors the editor into the preview', () {
    String? framedHtml(WidgetTester tester) {
      final frames = tester.widgetList<BrowserFrame>(find.byType(BrowserFrame));
      return frames.isEmpty ? null : frames.first.html;
    }

    testWidgets('the preview follows typing after the debounce tick',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveHtmlStudio(
              controller: controller,
              debounce: const Duration(milliseconds: 50),
            ),
          ),
        ),
      );

      const typed =
          '<!DOCTYPE html><html><body><h1>Typed live</h1></body></html>';
      controller.text = typed;
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(framedHtml(tester), prepareHtmlForPreview(typed));
      expect(framedHtml(tester), contains('Typed live'));
    });

    testWidgets('an out-of-band AI edit flushes through applyNow',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TextEditingController(
        text: '<!DOCTYPE html><html><body><p>before</p></body></html>',
      );
      addTearDown(controller.dispose);
      final key = GlobalKey<LiveHtmlStudioState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveHtmlStudio(key: key, controller: controller),
          ),
        ),
      );
      await tester.pump();

      const rewritten =
          '<!DOCTYPE html><html><body><p>after the AI edit</p></body></html>';
      controller.text = rewritten;
      key.currentState!.applyNow();
      await tester.pump();

      expect(framedHtml(tester), contains('after the AI edit'));
      expect(framedHtml(tester), isNot(contains('before')));
    });
  });
}
