import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_connect_africa/services/resource_text_extractor.dart';

/// Builds a real PDF the way a real producer does, so the extractor is tested
/// against actual FlateDecode streams and text operators rather than against a
/// string a test made up.
Future<Uint8List> buildPdf(List<String> paragraphs) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final p in paragraphs)
            pw.Paragraph(text: p, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
  return Uint8List.fromList(await doc.save());
}

/// Builds a real .docx: a zip whose `word/document.xml` holds `<w:p>`
/// paragraphs of `<w:t>` runs, which is the shape Word actually writes.
Uint8List buildDocx(List<String> paragraphs) {
  final body = paragraphs
      .map((p) => '<w:p><w:r><w:t>${_esc(p)}</w:t></w:r></w:p>')
      .join();
  final document =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body</w:body></w:document>';

  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'word/document.xml',
        utf8.encode(document).length,
        utf8.encode(document),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

void main() {
  // ── PDF, against a real generated file ──────────────────────────────────
  group('PDF extraction', () {
    test('reads back the text of a real PDF', () async {
      final bytes = await buildPdf([
        'Neutralisation is the reaction between an acid and a base.',
        'The products are a salt and water, and the pH moves toward seven.',
      ]);

      final result = extractPdfText(bytes);

      expect(result.ok, isTrue, reason: result.failure ?? '');
      expect(result.format, 'pdf');
      expect(result.text.toLowerCase(), contains('neutralisation'));
      expect(result.text.toLowerCase(), contains('salt and water'));
    });

    test('keeps separate paragraphs separable for chunking', () async {
      final bytes = await buildPdf([
        'First paragraph about acids and their behaviour in water.',
        'Second paragraph about bases and how they accept protons.',
      ]);

      final result = extractPdfText(bytes);

      expect(result.ok, isTrue, reason: result.failure ?? '');
      expect(result.text, contains('\n'),
          reason: 'without line breaks a whole document chunks as one blob');
    });

    test('a non-PDF is rejected, not silently parsed', () {
      final result = extractPdfText(
        Uint8List.fromList(utf8.encode('this is just text, not a pdf')),
      );
      expect(result.ok, isFalse);
      expect(result.failure, contains('not a readable PDF'));
    });

    test('a PDF with no text stream reports a scan, not a crash', () {
      // A structurally valid PDF header with no content streams at all.
      final result = extractPdfText(
        Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF\n')),
      );
      expect(result.ok, isFalse);
      expect(result.failure, contains('scan'));
    });
  });

  // ── DOCX, against a real zip ────────────────────────────────────────────
  group('DOCX extraction', () {
    test('reads back the text of a real .docx', () {
      final bytes = buildDocx([
        'Photosynthesis converts light energy into chemical energy.',
        'Chlorophyll absorbs light most strongly in the blue and red bands.',
      ]);

      final result = extractDocxText(bytes);

      expect(result.ok, isTrue, reason: result.failure ?? '');
      expect(result.text, contains('Photosynthesis'));
      expect(result.text, contains('Chlorophyll'));
    });

    // The trap: joining every <w:t> in the file turns a chapter into one
    // unbroken line, and chunkContent's paragraph preference never fires.
    test('paragraph boundaries survive as blank lines', () {
      final bytes = buildDocx(['First paragraph.', 'Second paragraph.']);
      final result = extractDocxText(bytes);
      expect(result.text, 'First paragraph.\n\nSecond paragraph.');
    });

    test('a zip with no document.xml is rejected', () {
      final archive = Archive()
        ..addFile(ArchiveFile('other.txt', 3, utf8.encode('abc')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = extractDocxText(bytes);
      expect(result.ok, isFalse);
      expect(result.failure, contains('no readable document'));
    });
  });

  // ── Plain formats ───────────────────────────────────────────────────────
  group('text and markup formats', () {
    test('plain text passes through with paragraphs intact', () {
      final bytes = Uint8List.fromList(
        utf8.encode('First line.\n\nSecond line.'),
      );
      final result = extractResourceText('notes.txt', bytes);
      expect(result.ok, isTrue);
      expect(result.text, 'First line.\n\nSecond line.');
    });

    test('HTML drops scripts and styles but keeps prose', () {
      final bytes = Uint8List.fromList(utf8.encode(
        '<html><head><style>p{color:red}</style></head>'
        '<body><p>Acids donate protons.</p>'
        '<script>alert(1)</script>'
        '<p>Bases accept them.</p></body></html>',
      ));
      final result = extractResourceText('notes.html', bytes);

      expect(result.ok, isTrue);
      expect(result.text, contains('Acids donate protons.'));
      expect(result.text, contains('Bases accept them.'));
      expect(result.text, isNot(contains('alert')));
      expect(result.text, isNot(contains('color:red')));
    });

    test('an unsupported type is named in the failure', () {
      final result = extractResourceText(
        'slides.pptx',
        Uint8List.fromList([1, 2, 3]),
      );
      expect(result.ok, isFalse);
      expect(result.failure, contains('.pptx'));
    });

    test('an empty file is rejected', () {
      final result = extractResourceText('notes.txt', Uint8List(0));
      expect(result.ok, isFalse);
      expect(result.failure, contains('empty'));
    });

    test('invalid UTF-8 falls back to Latin-1 instead of throwing', () {
      final bytes = Uint8List.fromList([
        ...utf8.encode('Caf'),
        0xE9, // é in Latin-1, invalid as standalone UTF-8
        ...utf8.encode(' notes for the class'),
      ]);
      final result = extractResourceText('notes.txt', bytes);
      expect(result.ok, isTrue);
      expect(result.text, contains('Caf'));
    });
  });

  // ── The mojibake gate ───────────────────────────────────────────────────
  //
  // A PDF using a subset-embedded font decodes to characters that are not the
  // ones on the page. That garbage has letters and spaces, so nothing
  // downstream rejects it — it would be stored and then presented to a student
  // as "verified facts from the teacher's lesson notes".
  group('looksLikeRealText', () {
    test('accepts ordinary prose', () {
      expect(
        looksLikeRealText(
          'Neutralisation is the reaction between an acid and a base.',
        ),
        isTrue,
      );
    });

    test('accepts prose with accents and punctuation', () {
      expect(
        looksLikeRealText('La photosynthèse transforme la lumière en énergie.'),
        isTrue,
      );
    });

    test('rejects symbol soup from a mis-mapped font', () {
      expect(looksLikeRealText(' ' * 20), isFalse);
    });

    test('rejects text that is mostly punctuation', () {
      expect(looksLikeRealText(r'### @@@ %%% &&& *** ((( ))) !!! ??? ;;;'),
          isFalse);
    });

    test('rejects a string too short to judge', () {
      expect(looksLikeRealText('ok'), isFalse);
    });

    test('rejects a run with no word-like letter groups', () {
      expect(looksLikeRealText('a b c d e f g h i j k l m n o p q r s t'),
          isFalse);
    });
  });

  // ── Normalization ───────────────────────────────────────────────────────
  group('normalizeExtractedText', () {
    test('rejoins a hyphenated line wrap', () {
      expect(
        normalizeExtractedText('photo-\nsynthesis is how plants eat'),
        'photosynthesis is how plants eat',
      );
    });

    test('collapses runs of blank lines to one paragraph break', () {
      expect(normalizeExtractedText('a\n\n\n\n\nb'), 'a\n\nb');
    });

    test('collapses horizontal whitespace but keeps paragraphs', () {
      expect(normalizeExtractedText('a     b\n\nc'), 'a b\n\nc');
    });

    test('strips null bytes', () {
      expect(normalizeExtractedText('a b'), 'ab');
    });
  });
}
