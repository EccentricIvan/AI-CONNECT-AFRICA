import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../ocr/ocr_engine.dart';
import '../resource_text_extractor.dart';
import 'diagram_detector.dart';

/// A page's embedded text and where each character sits.
class PageText {
  const PageText(this.text, this.boxes);
  final String text;
  final List<PageBox> boxes;
}

/// The pages of one open PDF. An interface so the routing below is testable
/// without PDFium.
abstract class PdfPageSource {
  int get pageCount;

  /// [page] is 1-based.
  Future<PageText> text(int page);

  /// [page] rendered so its longer side is [maxSide] pixels.
  Future<RenderedPage?> render(int page, {required int maxSide});

  Future<void> close();
}

/// PDFium through pdfrx, loaded from the app bundle — never downloaded.
class PdfrxPageSource implements PdfPageSource {
  PdfrxPageSource._(this._doc);

  final PdfDocument _doc;

  static Future<PdfrxPageSource> open(Uint8List bytes, {String? name}) async {
    await pdfrxFlutterInitialize();
    return PdfrxPageSource._(
      await PdfDocument.openData(bytes, sourceName: name ?? 'import-${bytes.length}'),
    );
  }

  @override
  int get pageCount => _doc.pages.length;

  @override
  Future<PageText> text(int page) async {
    final p = _doc.pages[page - 1];
    final t = await p.loadStructuredText();
    final boxes = <PageBox>[];
    final w = p.width, h = p.height;
    for (var i = 0; i < t.charRects.length && i < t.fullText.length; i++) {
      if (t.fullText[i].trim().isEmpty) continue;
      final r = t.charRects[i];
      boxes.add(PageBox(r.left / w, (h - r.top) / h, r.right / w, (h - r.bottom) / h));
    }
    return PageText(t.fullText, boxes);
  }

  @override
  Future<RenderedPage?> render(int page, {required int maxSide}) async {
    final p = _doc.pages[page - 1];
    final scale = maxSide / math.max(p.width, p.height);
    final image = await p.render(
      fullWidth: p.width * scale,
      fullHeight: p.height * scale,
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
    );
    if (image == null) return null;
    try {
      return RenderedPage(
        bgra: Uint8List.fromList(image.pixels),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> close() => _doc.dispose();
}

/// What reading a whole PDF produced.
class PdfExtraction {
  const PdfExtraction({
    required this.text,
    required this.pages,
    required this.ocrPages,
    required this.unreadablePages,
    required this.diagrams,
    this.cancelled = false,
  });

  final String text;
  final int pages;
  final int ocrPages;
  final int unreadablePages;
  final int diagrams;
  final bool cancelled;
}

/// Below this, a page's embedded text is a stray heading or page number on
/// what is really a scanned page.
const _minNativeChars = 40;

const _ocrMaxSide = 2000;
const _pictureCheckMaxSide = 400;

/// One page's readable text — embedded text, or OCR when the page is a scan
/// — or '' when it has none. No diagram markers.
Future<String> readablePageText(
  PdfPageSource source,
  int page, {
  OcrEngine? ocr,
}) async {
  final raw = (await source.text(page)).text;
  final native = normalizeExtractedText(raw);
  final nativeOk =
      looksLikeRealText(native) &&
      native.length >= _minNativeChars &&
      !mostlyUnreadable(raw);
  if (nativeOk) {
    return native;
  }
  // Without OCR, the readable part beats nothing.
  final fallback = looksLikeRealText(native) ? native : '';
  if (ocr == null) return fallback;
  try {
    final rendered = await source.render(
      page,
      maxSide: math.min(_ocrMaxSide, ocr.maxDimension),
    );
    if (rendered == null) return fallback;
    final text = normalizeExtractedText((await ocr.recognize(rendered)).text);
    return looksLikeRealText(text) ? text : fallback;
  } catch (e) {
    debugPrint('OCR failed on page $page: $e');
    return fallback;
  }
}

/// Reads every page: embedded text when the page has real text, OCR when it's
/// a scan, and a diagram marker where a picture or caption is. Nothing is
/// stored here, so cancelling leaves no trace.
Future<PdfExtraction> extractPdfPages(
  PdfPageSource source, {
  required String documentTitle,
  OcrEngine? ocr,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final total = source.pageCount;
  final pages = <String>[];
  var ocrPages = 0, unreadable = 0, diagrams = 0;

  for (var n = 1; n <= total; n++) {
    if (isCancelled?.call() ?? false) {
      return PdfExtraction(
        text: '',
        pages: total,
        ocrPages: ocrPages,
        unreadablePages: unreadable,
        diagrams: diagrams,
        cancelled: true,
      );
    }
    onProgress?.call(n - 1, total);

    final native = await source.text(n);
    var body = normalizeExtractedText(native.text);
    var boxes = native.boxes;
    RenderedPage? rendered;

    // A page partly in an unmapped font loses those lines when cleaned, so
    // it goes to OCR even if what is left would pass.
    final nativeOk =
        looksLikeRealText(body) &&
        body.length >= _minNativeChars &&
        !mostlyUnreadable(native.text);
    if (!nativeOk && ocr != null) {
      try {
        rendered = await source.render(
          n,
          maxSide: math.min(_ocrMaxSide, ocr.maxDimension),
        );
        if (rendered != null) {
          final result = await ocr.recognize(rendered);
          final text = normalizeExtractedText(result.text);
          if (looksLikeRealText(text)) {
            body = text;
            boxes = [
              for (final l in result.lines)
                PageBox(
                  l.left / rendered.width,
                  l.top / rendered.height,
                  (l.left + l.width) / rendered.width,
                  (l.top + l.height) / rendered.height,
                ),
            ];
            ocrPages++;
          }
        }
      } catch (e) {
        debugPrint('OCR failed on page $n: $e');
      }
    }

    final readable = looksLikeRealText(body);
    var hasPicture = false;
    var blank = false;
    try {
      rendered ??= await source.render(n, maxSide: _pictureCheckMaxSide);
      if (rendered != null) {
        hasPicture = countPictureRegions(rendered, readable ? boxes : const []) > 0;
        blank = !readable && body.trim().isEmpty && inkRatio(rendered) < 0.005;
      }
    } catch (e) {
      debugPrint('Picture check failed on page $n: $e');
    }
    if (blank) continue;

    if (readable) {
      final a = annotatePage(body, page: n, document: documentTitle, hasPicture: hasPicture);
      pages.add(a.text);
      diagrams += a.diagrams;
    } else if (hasPicture) {
      // A page that is only a picture is still worth pointing students to.
      pages.add(
        DiagramMarker(caption: DiagramMarker.kUncaptioned, page: n, document: documentTitle).format(),
      );
      diagrams++;
    } else {
      unreadable++;
    }
  }
  onProgress?.call(total, total);

  return PdfExtraction(
    text: normalizeExtractedText(pages.join('\n\n')),
    pages: total,
    ocrPages: ocrPages,
    unreadablePages: unreadable,
    diagrams: diagrams,
  );
}
