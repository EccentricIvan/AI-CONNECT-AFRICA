import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ai_connect_africa/services/ocr/ocr_engine.dart';
import 'package:ai_connect_africa/services/ocr/windows_ocr_engine.dart';
import 'package:ai_connect_africa/services/pdf/diagram_detector.dart';
import 'package:ai_connect_africa/services/pdf/pdf_page_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A "scanned" page: prose, a drawing and its caption painted as pixels, so
/// the PDF holds only an image and no text at all.
Future<Uint8List> _scannedPagePng() async {
  const w = 1240.0, h = 1754.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(const ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

  double y = 120;
  void line(String text, {double size = 34}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
      ..addText(text);
    final p = b.build()..layout(const ui.ParagraphConstraints(width: w - 200));
    canvas.drawParagraph(p, ui.Offset(100, y));
    y += size * 1.8;
  }

  line('Photosynthesis happens in the leaves of green plants.');
  line('Chlorophyll absorbs sunlight and the plant makes glucose.');
  line('Oxygen is released into the air as a waste product.');

  final ink = ui.Paint()
    ..color = const ui.Color(0xFF000000)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 6;
  canvas
    ..drawOval(const ui.Rect.fromLTWH(250, 520, 740, 520), ink)
    ..drawLine(const ui.Offset(620, 520), const ui.Offset(620, 1040), ink)
    ..drawLine(const ui.Offset(300, 780), const ui.Offset(940, 780), ink);
  y = 1110;
  line('Figure 1: Parts of a leaf');

  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a scanned PDF is read by PDFium + on-device OCR, with its diagram marked',
      (tester) async {
    await tester.runAsync(() async {
      final png = await _scannedPagePng();
      final doc = pw.Document()
        ..addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ));
      final bytes = Uint8List.fromList(await doc.save());

      final OcrEngine? ocr = Platform.isWindows ? await WindowsOcrEngine.create() : null;
      expect(ocr, isNotNull, reason: 'no Windows OCR language on this PC');

      final source = await PdfrxPageSource.open(bytes, name: 'scan-smoke');
      final watch = Stopwatch()..start();
      final result = await extractPdfPages(source, documentTitle: 'Leaf Notes', ocr: ocr);
      await source.close();
      // ignore: avoid_print
      print('OCR page took ${watch.elapsedMilliseconds} ms:\n${result.text}');

      expect(result.ocrPages, 1);
      expect(result.unreadablePages, 0);
      expect(result.text.toLowerCase(), contains('photosynthesis'));
      expect(result.text.toLowerCase(), contains('chlorophyll'));
      expect(result.text.toLowerCase(), contains('oxygen is released'));
      final marker = DiagramMarker.parseAll(result.text).single;
      expect(marker.caption, startsWith('Figure 1'));
      expect(marker.page, 1);
    });
  });
}
