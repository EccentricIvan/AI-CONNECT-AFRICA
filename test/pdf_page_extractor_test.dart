import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/services/ocr/ocr_engine.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/pdf/diagram_detector.dart';
import 'package:ai_connect_africa/services/pdf/pdf_page_extractor.dart';
import 'package:ai_connect_africa/services/resource_import_service.dart';

const _prose =
    'Photosynthesis is the process by which green plants use sunlight, water '
    'and carbon dioxide to make glucose and release oxygen into the air.';

enum Kind { text, scan, picture, blank, rules, mixed }

/// One clean line, then lines in a font with no text map.
const _garbageLine = '\u0001~\u0002P\u0003\u0004\u0005\u0006W\u0007\u0008K\u000e\u000f~\u0010P\u0011';
const _mixed =
    'Chapter 2: Industrial processes in the chemical industry today\n'
    '$_garbageLine\n$_garbageLine\n$_garbageLine\n$_garbageLine';

RenderedPage _render(Kind kind, int maxSide) {
  final w = (maxSide * 0.75).round(), h = maxSide;
  final px = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  void box(int l, int t, int r, int b) {
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        final i = (y * w + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = 0;
      }
    }
  }

  switch (kind) {
    case Kind.picture:
      final l = w ~/ 5, t = h ~/ 3, r = w * 4 ~/ 5, b = h * 2 ~/ 3;
      box(l, t, r, t + 3);
      box(l, b - 3, r, b);
      box(l, t, l + 3, b);
      box(r - 3, t, r, b);
      box(l, (t + b) ~/ 2, r, (t + b) ~/ 2 + 3);
    case Kind.rules:
      for (var y = h ~/ 5; y < h * 4 ~/ 5; y += h ~/ 12) {
        box(w ~/ 10, y, w * 9 ~/ 10, y + 3);
      }
    case Kind.text || Kind.scan || Kind.blank || Kind.mixed:
      break;
  }
  return RenderedPage(bgra: px, width: w, height: h);
}

class FakePdf implements PdfPageSource {
  FakePdf(this.kinds);
  final List<Kind> kinds;
  final rendered = <int>[];
  bool closed = false;

  @override
  int get pageCount => kinds.length;

  @override
  Future<PageText> text(int page) async =>
      PageText(switch (kinds[page - 1]) {
        Kind.text => _prose,
        Kind.mixed => _mixed,
        _ => '',
      }, const []);

  @override
  Future<RenderedPage?> render(int page, {required int maxSide}) async {
    rendered.add(page);
    return _render(kinds[page - 1], maxSide);
  }

  @override
  Future<void> close() async => closed = true;
}

class FakeOcr extends OcrEngine {
  FakeOcr(this.reply);
  final String reply;
  var calls = 0;

  @override
  int get maxDimension => 1000;

  @override
  Future<OcrResult> recognize(RenderedPage page) async {
    calls++;
    return OcrResult([OcrLine(reply, 10, 10, page.width - 20.0, 30)]);
  }
}

void main() {
  group('page routing', () {
    test('a page with real text never goes to OCR', () async {
      final ocr = FakeOcr(_prose);
      final r = await extractPdfPages(FakePdf([Kind.text]), documentTitle: 'Bio', ocr: ocr);
      expect(ocr.calls, 0);
      expect(r.text, contains('Photosynthesis'));
      expect(r.ocrPages, 0);
    });

    test('a page mostly in an unmapped font still goes to OCR', () async {
      final ocr = FakeOcr(_prose);
      final r = await extractPdfPages(FakePdf([Kind.mixed]), documentTitle: 'Bio', ocr: ocr);
      expect(ocr.calls, 1);
      expect(r.text, contains('Photosynthesis'));

      final page = await readablePageText(FakePdf([Kind.mixed]), 1, ocr: FakeOcr(_prose));
      expect(page, contains('Photosynthesis'));
      // Without OCR the readable part is kept, never the symbols.
      final bare = await readablePageText(FakePdf([Kind.mixed]), 1);
      expect(bare, startsWith('Chapter 2'));
      expect(bare, isNot(contains('~')));
    });

    test('a scanned page is read by OCR', () async {
      final ocr = FakeOcr(_prose);
      final r = await extractPdfPages(FakePdf([Kind.text, Kind.scan]), documentTitle: 'Bio', ocr: ocr);
      expect(ocr.calls, 1);
      expect(r.ocrPages, 1);
      expect(r.unreadablePages, 0);
    });

    test('OCR garbage is dropped and the page counted unreadable', () async {
      final r = await extractPdfPages(
        FakePdf([Kind.text, Kind.rules]),
        documentTitle: 'Bio',
        ocr: FakeOcr('€‰Ł‡ ~~ ## ;;; ||'),
      );
      expect(r.text, isNot(contains('€')));
      expect(r.ocrPages, 0);
      expect(r.unreadablePages, 1);
    });

    test('without OCR a scanned page is unreadable, not a crash', () async {
      final r = await extractPdfPages(FakePdf([Kind.text, Kind.rules]), documentTitle: 'Bio');
      expect(r.unreadablePages, 1);
    });

    test('a blank page is skipped quietly', () async {
      final r = await extractPdfPages(FakePdf([Kind.text, Kind.blank]), documentTitle: 'Bio');
      expect(r.unreadablePages, 0);
    });

    test('a picture-only page becomes a marker pointing at its page', () async {
      final r = await extractPdfPages(FakePdf([Kind.text, Kind.picture]), documentTitle: 'Bio');
      expect(r.diagrams, 1);
      final m = DiagramMarker.parseAll(r.text).single;
      expect(m.page, 2);
      expect(m.document, 'Bio');
    });

    test('cancelling stops before the next page and returns nothing', () async {
      final pdf = FakePdf([Kind.text, Kind.text, Kind.text]);
      var asked = 0;
      final r = await extractPdfPages(pdf, documentTitle: 'Bio', isCancelled: () => ++asked > 1);
      expect(r.cancelled, isTrue);
      expect(r.text, isEmpty);
      expect(pdf.rendered, [1]);
    });

    test('progress reports every page', () async {
      final seen = <(int, int)>[];
      await extractPdfPages(
        FakePdf([Kind.text, Kind.text]),
        documentTitle: 'Bio',
        onProgress: (d, t) => seen.add((d, t)),
      );
      expect(seen, [(0, 2), (1, 2), (2, 2)]);
    });
  });

  group('importing a PDF', () {
    late OticDatabase db;
    late OfflineStorageService storage;

    setUp(() {
      db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
      storage = OfflineStorageService(db);
    });
    tearDown(() => db.close());

    ResourceImportService importer(FakePdf pdf, {OcrEngine? ocr}) => ResourceImportService(
      storage,
      ocr: () async => ocr,
      openPdf: (_, _) async => pdf,
    );

    test('reports scanned pages and diagrams, and the markers are stored', () async {
      final pdf = FakePdf([Kind.text, Kind.scan, Kind.picture]);
      final report = await importer(pdf, ocr: FakeOcr(_prose)).importBytes(
        fileName: 'Biology Term 1.pdf',
        bytes: Uint8List.fromList([1]),
        subjectId: 'biology',
      );
      expect(report.ok, isTrue, reason: report.failure);
      expect(report.pageCount, 3);
      // The fake OCR reads text on both image pages; the picture page keeps
      // its text and still gets a marker for the picture.
      expect(report.ocrPages, 2);
      expect(report.diagramCount, 1);
      expect(pdf.closed, isTrue);
      final stored = (await storage.chunksForSubject(subjectId: 'biology'))
          .map((r) => r.contentChunk)
          .join('\n');
      expect(stored, contains('page 3 of the PDF "Biology Term 1"'));
    });

    test('a scan on a device without OCR says how to fix it', () async {
      final report = await importer(FakePdf([Kind.rules])).importBytes(
        fileName: 'scan.pdf',
        bytes: Uint8List.fromList([1]),
        subjectId: 'biology',
      );
      expect(report.ok, isFalse);
      expect(report.failure, contains('scan'));
      expect(report.failure, contains(ocrUnavailableReason()));
    });

    test('a cancelled import stores nothing', () async {
      final report = await ResourceImportService(
        storage,
        openPdf: (_, _) async => FakePdf([Kind.text, Kind.text]),
      ).importBytes(
        fileName: 'Notes.pdf',
        bytes: Uint8List.fromList([1]),
        subjectId: 'biology',
        isCancelled: () => true,
      );
      expect(report.cancelled, isTrue);
      expect(await storage.hasAnyResources(), isFalse);
    });

    test('a file PDFium cannot open falls back to the built-in reader', () async {
      final report = await ResourceImportService(
        storage,
        openPdf: (_, _) => Future.error(StateError('not a pdf')),
      ).importBytes(
        fileName: 'scan.pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
        subjectId: 'biology',
      );
      expect(report.ok, isFalse);
      expect(report.failure, contains('scan'));
    });
  });
}
