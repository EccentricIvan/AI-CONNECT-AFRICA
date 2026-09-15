import 'dart:io';

import 'package:ai_connect_africa/features/app_dev_lab/app_build_intent.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_schema_studio.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/preview_contract.dart';

/// Two questions about the web and app builders:
///
/// 1. Is the preview strictly the code in the editor on the left?
/// 2. Is it a browser-like sandbox that renders that code offline?
///
/// `preview_mirrors_editor_test.dart` covers (1) for the HTML builders. These
/// tests cover the offline half of (2), the JavaScript execution surface, and
/// the App Dev Lab schema path, which is a different preview engine entirely.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Anything that would make the page reach for the network.
  final networkRef = RegExp(
    r'''(src|href)\s*=\s*['"]?\s*(https?:)?//|@import\s+url\(\s*['"]?\s*(https?:)?//|fetch\(\s*['"]https?:|cdn\.|fonts\.googleapis|unpkg\.com|jsdelivr''',
    caseSensitive: false,
  );

  List<File> templatesIn(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.html'))
        .toList();
  }

  group('the preview sandbox renders with no network', () {
    test('no builder template reaches for the network', () {
      final files = templatesIn('assets/templates');
      expect(files, isNotEmpty, reason: 'no templates found to check');

      for (final file in files) {
        final match = networkRef.firstMatch(file.readAsStringSync());
        expect(
          match,
          isNull,
          reason: '${file.path} would need the internet: "${match?.group(0)}"',
        );
      }
    });

    test('preparing a document for the preview never adds a network call', () {
      for (final file in templatesIn('assets/templates')) {
        final prepared = prepareHtmlForPreview(file.readAsStringSync());
        expect(
          networkRef.hasMatch(prepared),
          isFalse,
          reason: '${file.path} gained a network reference in the preview',
        );
      }
    });

    test('the empty-state document is self-contained', () {
      final empty = prepareHtmlForPreview('');
      expect(networkRef.hasMatch(empty), isFalse);
      expect(empty, contains('Nothing to preview yet'));
    });

    test('both coder prompts forbid CDN links', () {
      for (final path in const [
        'lib/features/site_builder/site_build_coder.dart',
        'lib/features/app_dev_lab/app_build_coder.dart',
      ]) {
        expect(
          File(path).readAsStringSync().toLowerCase(),
          contains('no cdn'),
          reason: '$path no longer tells the model to stay offline',
        );
      }
    });
  });

  group('the sandbox is handed a live page, not sanitised text', () {
    const interactive = '<!DOCTYPE html>\n'
        '<html><head><title>Counter</title></head>\n'
        '<body>\n'
        '<button id="b">Count</button><span id="n">0</span>\n'
        '<script>\n'
        "let n = Number(localStorage.getItem('n') || 0);\n"
        "document.getElementById('b').onclick = () => {\n"
        "  n++; localStorage.setItem('n', n);\n"
        "  document.getElementById('n').textContent = n;\n"
        '};\n'
        '</script>\n'
        '</body></html>';

    test('script, handlers and localStorage survive to the engine', () {
      final prepared = prepareHtmlForPreview(interactive);
      expect(prepared, contains('<script>'));
      expect(prepared, contains('localStorage.setItem'));
      expect(prepared, contains('onclick'));
      // Unchanged, not merely present.
      expect(prepared.trim(), interactive.trim());
    });

    test('the document title drives the address bar, as a browser would', () {
      expect(htmlDocumentTitle(interactive), 'Counter');
      expect(htmlDocumentTitle('<html><body>x</body></html>'), 'index.html');
    });

    testWidgets('the live studio hands that page to a BrowserFrame',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TextEditingController(text: interactive);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LiveHtmlStudio(controller: controller)),
        ),
      );
      await tester.pump();

      final frame = tester.widget<BrowserFrame>(find.byType(BrowserFrame));
      expect(frame.html, contains('localStorage.setItem'));
      expect(frame.html, prepareHtmlForPreview(interactive));
      for (final invented in kInventedPreviewContent) {
        expect(frame.html, isNot(contains(invented)));
      }
    });

    test('Android and Windows both declare an embedded engine', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('webview_flutter_android'),
        reason: 'Android has no preview engine',
      );
      expect(
        pubspec,
        contains('webview_flutter_windows'),
        reason: 'Windows has no preview engine',
      );
    });
  });

  // ORPHANED PATH. /applab no longer routes through AppSchemaStudio — the App
  // Dev Lab is now lesson-based on CodeLabScaffold, with a real browser
  // preview (see code_lab_lessons_test.dart). The widget and its schema
  // interpreter still compile and are still covered here, but no student can
  // reach them, so the substitution defect below is off the shipped path.
  // Delete this group when app_schema_studio.dart goes.
  group('AppSchemaStudio (no longer routed) previews a schema', () {
    AppBuildIntent intentFor() => AppBuildIntent(
          appTypeId: 'todo',
          appTypeName: 'To-do app',
          themeId: 'calm',
          themeName: 'Calm',
          themePrimary: '#2563EB',
          answers: const {'app_name': 'Chore Tracker'},
          features: const ['Add task'],
        );

    Future<void> pump(WidgetTester tester, TextEditingController c) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSchemaStudio(controller: c, intent: intentFor()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a valid schema previews only the nodes the student wrote',
        (tester) async {
      final controller = TextEditingController(
        text: 'OTIC_UI_V1\n'
            'title: Chore Tracker\n'
            '---\n'
            'Type: Header, Text: My Chores\n'
            'Type: Button, Text: Add chore, Action: Alert\n',
      );
      addTearDown(controller.dispose);
      await pump(tester, controller);

      expect(find.text('My Chores'), findsOneWidget);
      expect(find.text('Add chore'), findsOneWidget);
      // None of the generated template's filler.
      expect(find.text('Sample item 1'), findsNothing);
      expect(find.text('Quick try'), findsNothing);
    });

    testWidgets(
        'KNOWN DEFECT: an unparseable schema discards the student\'s code - '
        'the one preview surface that does not mirror the editor',
        (tester) async {
      final controller = TextEditingController(text: 'not a schema at all');
      addTearDown(controller.dispose);
      await pump(tester, controller);

      await tester.tap(find.text('Apply Changes').first);
      await tester.pump();

      // Pinned so the behaviour is visible, NOT endorsed. `_applyNow()` in
      // app_schema_studio.dart substitutes fallbackUiSchemaSource() into both
      // the preview and the editor, so what the student typed is lost rather
      // than shown back to them with an error.
      //
      // When that is fixed, invert this: the student's text must survive and
      // the preview should report the parse failure instead.
      expect(controller.text, isNot(contains('not a schema at all')));
      expect(controller.text, contains('OTIC_UI_V1'));
    });
  });
}
