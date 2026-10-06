import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/notes/pdf_highlights.dart';
import 'package:ai_connect_africa/features/notes/pdf_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs the real reader (real PDFium) on a note PDF already saved on this
/// PC: `PDF_READER_TEST_FILE`, else the newest file in the app's
/// `otic_note_pdfs`. Works on a temp copy and mock prefs, so the app's own
/// data is never touched. Screenshots go to `PDF_READER_TEST_SHOTS`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  File findSavedPdf() {
    final explicit = Platform.environment['PDF_READER_TEST_FILE'];
    if (explicit != null && explicit.isNotEmpty) return File(explicit);
    final dir = Directory(
      '${Platform.environment['APPDATA']}\\com.otic\\AI Connect Africa\\otic_note_pdfs',
    );
    final pdfs = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.pdf'),
    ).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return pdfs.first;
  }

  final shotKey = GlobalKey();
  final shotsDir = Platform.environment['PDF_READER_TEST_SHOTS'] ??
      Directory.systemTemp.path;

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$shotsDir\\$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Future<PdfViewerController> pumpReader(
    WidgetTester tester,
    String path,
    String memoryKey,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeStudentProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          home: RepaintBoundary(
            key: shotKey,
            child: PdfReader(
              key: UniqueKey(),
              path: path,
              title: 'Saved note',
              memoryKey: memoryKey,
            ),
          ),
        ),
      ),
    );
    late PdfViewerController controller;
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final viewers = find.byType(PdfViewer);
      if (viewers.evaluate().isEmpty) continue;
      controller = tester.widget<PdfViewer>(viewers).controller!;
      if (controller.isReady) break;
    }
    expect(controller.isReady, isTrue, reason: 'PDF never finished loading');
    // Let the first pages render.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    return controller;
  }

  testWidgets('a saved note PDF opens, highlights persist, copy is blocked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    SharedPreferences.setMockInitialValues({});
    await pdfrxFlutterInitialize();

    final source = findSavedPdf();
    final sha = source.uri.pathSegments.last.replaceAll('.pdf', '');
    final copy = File('${Directory.systemTemp.path}\\reader_test_$sha.pdf');
    await tester.runAsync(() => source.copy(copy.path));
    // ignore: avoid_print
    print('Testing ${source.path} (${source.lengthSync()} bytes)');

    // ── Opens, real pages, toolbar "of N" ─────────────────────────────
    var controller = await pumpReader(tester, copy.path, sha);
    final pages = controller.document.pages.length;
    // ignore: avoid_print
    print('Pages: $pages');
    expect(pages, greaterThan(0));
    expect(find.text('of $pages'), findsOneWidget);
    expect(find.byTooltip('Print'), findsNothing);
    expect(find.byTooltip('Download'), findsNothing);
    await shot(tester, '1_opened');

    // Does page 1 carry real text (not only a scan)?
    final text = await tester.runAsync(
      () => controller.document.pages.first.loadStructuredText(),
    );
    // ignore: avoid_print
    print('Page 1 text chars: ${text!.fullText.length}');
    expect(
      text.fullText.trim(),
      isNotEmpty,
      reason: 'page 1 is a scan with no text layer, nothing to highlight',
    );

    // ── Select text: the menu offers Highlight, never Copy ───────────
    await tester.runAsync(
      () => controller.textSelectionDelegate.selectWord(
        _firstWordPosition(controller, text),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      controller.textSelectionDelegate.hasSelectedText,
      isTrue,
      reason: 'selecting a word on page 1 failed',
    );
    await shot(tester, '2_selected_menu');
    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);

    // ── Ctrl+C copies nothing ─────────────────────────────────────────
    await tester.runAsync(
      () => Clipboard.setData(const ClipboardData(text: 'SENTINEL')),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));
    final clip = await tester.runAsync(
      () => Clipboard.getData(Clipboard.kTextPlain),
    );
    expect(clip?.text, 'SENTINEL', reason: 'Ctrl+C copied the PDF text');

    // ── Highlight it ──────────────────────────────────────────────────
    await tester.tap(find.text('Highlight'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = loadPdfHighlights(prefs, pdfHighlightKey(null, sha));
    // ignore: avoid_print
    print('Saved highlights: ${[for (final h in saved) '"${h.text}" p${h.page} ${h.rects}']}');
    expect(saved, hasLength(1));
    expect(saved.single.page, 1);
    expect(saved.single.text, isNotEmpty);
    await shot(tester, '3_highlighted');

    // ── Highlights tab lists it ───────────────────────────────────────
    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Highlights'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text(saved.single.text), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    await shot(tester, '4_highlights_tab');

    // ── Reopen: the highlight is still there ──────────────────────────
    await tester.pumpWidget(const SizedBox());
    controller = await pumpReader(tester, copy.path, sha);
    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Highlights'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text(saved.single.text), findsOneWidget);

    // ── Remove it from the list ───────────────────────────────────────
    await tester.tap(find.byTooltip('Remove highlight'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('No highlights'), findsOneWidget);
    expect(prefs.getString(pdfHighlightKey(null, sha)), isNull);

    // Close the reader first: Windows won't delete a file PDFium holds open.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        await copy.delete();
      } catch (_) {}
    });
  });
}

/// Document position of the middle of page 1's first real word.
Offset _firstWordPosition(PdfViewerController controller, PdfPageText text) {
  final page = controller.document.pages.first;
  final pageRect = controller.layout.pageLayouts.first;
  // A visible body word; the first word can be hidden text behind a banner.
  final want = Platform.environment['PDF_READER_TEST_WORD'] ?? 'Curriculum';
  var i = text.fullText.indexOf(want);
  if (i < 0) i = text.fullText.indexOf(RegExp(r'[A-Za-z]{3,}'));
  // ignore: avoid_print
  print('Selecting at char $i: rect ${text.charRects[i < 0 ? 0 : i]}, '
      'page ${page.width}x${page.height}, layout $pageRect');
  final r = text.charRects[i < 0 ? 0 : i]
      .toRect(page: page, scaledPageSize: pageRect.size);
  return pageRect.topLeft + r.center;
}
