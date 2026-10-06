import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/features/notes/pdf_highlights.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a two-line selection becomes one box per line', () {
    // "ab\ncd": two chars on a line at y 700–710, a zero-width break, two
    // chars on the next line at y 680–690.
    const text = PdfPageText(
      pageNumber: 3,
      fullText: 'ab\ncd',
      charRects: [
        PdfRect(10, 710, 20, 700),
        PdfRect(20, 710, 30, 700),
        PdfRect(30, 710, 30, 700),
        PdfRect(10, 690, 20, 680),
        PdfRect(20, 690, 25, 680),
      ],
      fragments: [],
    );
    final rects = pdfLineRects(
      const PdfPageTextRange(pageText: text, start: 0, end: 5),
    );
    expect(rects, const [PdfRect(10, 710, 30, 700), PdfRect(10, 690, 25, 680)]);
  });

  test('highlights round-trip per learner and overlap by page', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final key = pdfHighlightKey(7, 'abc');
    expect(key, 'pdf_hl_s7_abc');

    const h = PdfHighlight(
      id: '1',
      page: 2,
      rects: [PdfRect(10, 710, 30, 700)],
      text: 'heart',
    );
    await savePdfHighlights(prefs, key, [h]);

    final loaded = loadPdfHighlights(prefs, key).single;
    expect(loaded.page, 2);
    expect(loaded.text, 'heart');
    expect(loaded.rects, h.rects);
    expect(loaded.overlaps(2, const [PdfRect(15, 705, 18, 702)]), isTrue);
    expect(loaded.overlaps(3, const [PdfRect(15, 705, 18, 702)]), isFalse);
    expect(loadPdfHighlights(prefs, pdfHighlightKey(8, 'abc')), isEmpty);

    await savePdfHighlights(prefs, key, []);
    expect(prefs.getString(key), isNull);
  });
}
