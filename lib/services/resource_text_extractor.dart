/// Turns an uploaded file into plain text, entirely on-device.
///
/// Every decoder here is pure Dart and runs with the radio off. Nothing is
/// uploaded, and no format is handled by shelling out to a tool that might not
/// exist on a school laptop.
///
/// The contract that matters: extraction either produces text a person would
/// recognize, or it **fails loudly**. It must never return mojibake, because
/// the retrieval frame presents whatever comes back as "verified facts from the
/// teacher's lesson notes" — plausible-looking garbage stored under that label
/// is worse than a file that was rejected.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';



/// What an extraction attempt produced.
class ExtractionResult {
  const ExtractionResult({
    required this.text,
    required this.format,
    this.failure,
  });

  const ExtractionResult.failed(this.format, this.failure) : text = '';

  /// Extracted plain text. Empty when [failure] is set.
  final String text;

  /// Lower-case extension the file was treated as, e.g. `pdf`.
  final String format;

  /// Teacher-readable reason extraction did not work. Null on success.
  final String? failure;

  bool get ok => failure == null && text.trim().isNotEmpty;
}

/// Extensions the importer offers in its file picker.
const kSupportedResourceExtensions = [
  'pdf',
  'docx',
  'txt',
  'md',
  'markdown',
  'csv',
  'html',
  'htm',
  'json',
];

/// Extracts text from [bytes], dispatching on [fileName]'s extension.
ExtractionResult extractResourceText(String fileName, Uint8List bytes) {
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';

  if (bytes.isEmpty) {
    return ExtractionResult.failed(ext, 'That file is empty.');
  }

  switch (ext) {
    case 'pdf':
      return extractPdfText(bytes);
    case 'docx':
      return extractDocxText(bytes);
    case 'html':
    case 'htm':
      return _wrap(ext, () => _htmlToText(_decodeText(bytes)));
    case 'txt':
    case 'md':
    case 'markdown':
    case 'csv':
    case 'json':
      return _wrap(ext, () => _decodeText(bytes));
    default:
      return ExtractionResult.failed(
        ext,
        ext.isEmpty
            ? 'That file has no file type, so it cannot be read.'
            : 'Files of type ".$ext" cannot be read. '
                'Try PDF, Word, or a plain text file.',
      );
  }
}

ExtractionResult _wrap(String format, String Function() run) {
  try {
    final text = normalizeExtractedText(run());
    if (text.trim().isEmpty) {
      return ExtractionResult.failed(format, 'No text could be read from that file.');
    }
    return ExtractionResult(text: text, format: format);
  } catch (e) {
    return ExtractionResult.failed(format, 'That file could not be read ($e).');
  }
}

/// UTF-8 with a Latin-1 fallback, since a teacher's .txt may be either.
String _decodeText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

String _htmlToText(String source) {
  final doc = html_parser.parse(source);
  for (final node in doc.querySelectorAll('script, style')) {
    node.remove();
  }
  // Block elements become paragraph breaks so chunking has boundaries to find.
  for (final node in doc.querySelectorAll('p, div, br, li, h1, h2, h3, h4, h5, h6')) {
    node.append(html_parser.parseFragment('\n\n').clone(true));
  }
  return doc.body?.text ?? doc.documentElement?.text ?? '';
}

// ── .docx ────────────────────────────────────────────────────────────────

/// Extracts text from a Word document.
///
/// A .docx is a zip; the prose lives in `word/document.xml` as `<w:t>` runs
/// nested inside `<w:p>` paragraphs. Text is joined **per paragraph**, not per
/// run: concatenating every `<w:t>` in the file turns a whole chapter into one
/// unbroken line, which then defeats the paragraph-boundary preference in
/// `chunkContent` and forces a hard cut every 500 characters.
ExtractionResult extractDocxText(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? doc;
    for (final f in archive.files) {
      if (f.name == 'word/document.xml') {
        doc = f;
        break;
      }
    }
    if (doc == null) {
      return const ExtractionResult.failed(
        'docx',
        'That Word file has no readable document inside it.',
      );
    }

    final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
    final paragraphs = <String>[];
    for (final p in xml.findAllElements('w:p')) {
      final buf = StringBuffer();
      for (final node in p.descendantElements) {
        if (node.name.qualified == 'w:t') {
          buf.write(node.innerText);
        } else if (node.name.qualified == 'w:tab') {
          buf.write('\t');
        } else if (node.name.qualified == 'w:br') {
          buf.write('\n');
        }
      }
      final line = buf.toString().trim();
      if (line.isNotEmpty) paragraphs.add(line);
    }

    final text = normalizeExtractedText(paragraphs.join('\n\n'));
    if (text.trim().isEmpty) {
      return const ExtractionResult.failed(
        'docx',
        'That Word file has no text in it.',
      );
    }
    return ExtractionResult(text: text, format: 'docx');
  } catch (e) {
    return ExtractionResult.failed('docx', 'That Word file could not be read ($e).');
  }
}

// ── .pdf ─────────────────────────────────────────────────────────────────

/// Extracts text from a PDF, best-effort, with no native dependency.
///
/// ## What this does
///
/// Walks the file's `stream … endstream` objects, inflates the `FlateDecode`
/// ones, and reads the text-showing operators out of the resulting content
/// streams: `(text) Tj`, `[(a) -20 (b)] TJ`, and the `'` / `"` line variants.
/// Positioning operators (`Td`, `TD`, `T*`) become line breaks so paragraphs
/// survive into [chunkContent].
///
/// ## What this deliberately does not do
///
/// It does not resolve embedded font CMaps. A PDF produced with a subset-
/// embedded font maps its bytes through a private encoding, and decoding those
/// bytes as text yields characters that are not the ones on the page — garbage
/// that *looks* like content. [looksLikeRealText] is the gate that catches
/// this: a stream that fails it is discarded rather than stored.
///
/// It also cannot read scanned pages, which contain images and no text at all.
/// That needs OCR, which is out of scope for a device already running two
/// models. Such a file is reported as a scan, not as an error.
ExtractionResult extractPdfText(Uint8List bytes) {
  try {
    final raw = latin1.decode(bytes, allowInvalid: true);
    if (!raw.startsWith('%PDF')) {
      return const ExtractionResult.failed(
        'pdf',
        'That file is not a readable PDF.',
      );
    }

    final pieces = <String>[];
    for (final stream in _pdfStreams(bytes, raw)) {
      final text = _textFromContentStream(stream);
      if (text.trim().isEmpty) continue;
      // Per stream, not per document: one bad font should not discard a
      // whole textbook, and one good stream should not smuggle in garbage.
      if (!looksLikeRealText(text)) continue;
      pieces.add(text);
    }

    final text = normalizeExtractedText(pieces.join('\n\n'));
    if (text.trim().isEmpty) {
      return const ExtractionResult.failed(
        'pdf',
        'No text could be read from that PDF. If it is a scan or a photo of '
        'a page, type or paste the notes in instead.',
      );
    }
    return ExtractionResult(text: text, format: 'pdf');
  } catch (e) {
    return ExtractionResult.failed('pdf', 'That PDF could not be read ($e).');
  }
}

/// Decoded content of every stream object in the file.
Iterable<String> _pdfStreams(Uint8List bytes, String raw) sync* {
  var index = 0;
  while (true) {
    final start = raw.indexOf('stream', index);
    if (start < 0) break;
    final end = raw.indexOf('endstream', start);
    if (end < 0) break;

    // The dictionary immediately before tells us how the bytes are encoded.
    final dictStart = raw.lastIndexOf('<<', start);
    final dict = dictStart < 0 ? '' : raw.substring(dictStart, start);

    var from = start + 'stream'.length;
    if (from < raw.length && raw.codeUnitAt(from) == 13) from++; // CR
    if (from < raw.length && raw.codeUnitAt(from) == 10) from++; // LF

    if (from < end) {
      final slice = Uint8List.sublistView(bytes, from, end);
      if (dict.contains('/FlateDecode')) {
        final inflated = _inflate(slice);
        if (inflated != null) yield latin1.decode(inflated, allowInvalid: true);
      } else if (!dict.contains('/Filter')) {
        // Uncompressed content stream.
        yield latin1.decode(slice, allowInvalid: true);
      }
      // Any other filter (DCTDecode images, LZW, …) carries no prose we can
      // reach without a full PDF stack; skipping is correct, not a failure.
    }
    index = end + 'endstream'.length;
  }
}

/// Inflates a `FlateDecode` stream.
///
/// Tries zlib framing first (what the spec calls for and what almost every
/// producer emits), then raw deflate. Some writers emit a stream whose leading
/// whitespace was not stripped, which shifts the zlib header and fails the
/// first attempt while the second succeeds — hence both, rather than one.
List<int>? _inflate(Uint8List data) {
  if (data.isEmpty) return null;
  try {
    final out = const ZLibDecoder().decodeBytes(data, verify: false);
    if (out.isNotEmpty) return out;
  } catch (_) {
    // Fall through to raw deflate.
  }
  try {
    final out = Inflate(data).getBytes();
    if (out.isNotEmpty) return out;
  } catch (_) {
    // Not inflatable — an image or an unsupported filter.
  }
  return null;
}

/// Pulls the shown strings out of one decoded content stream.
///
/// The subtlety is when a positioning operator means "new line" and when it
/// means "next word on the same line". Producers vary: some emit one `Td` per
/// line, but others — including the `pdf` package this project already uses
/// for certificates — position **every single word** with its own `Td`.
/// Treating every `Td` as a line break turns such a document into one word per
/// line, which is unreadable and leaves `chunkContent` no sentence boundaries
/// to cut on.
///
/// So the operands are tracked: `tx ty Td` is a line break only when `ty` is
/// non-zero, and `a b c d e f Tm` only when the `f` (vertical) component
/// actually moved. A purely horizontal move emits a space instead.
String _textFromContentStream(String content) {
  final out = StringBuffer();
  final operands = <double>[];
  final ctmStack = <double>[];
  double? lastY;
  var ctmY = 0.0;
  var textY = 0.0;
  var pendingNewline = false;
  var pendingSpace = false;
  var i = 0;

  /// Same vertical position as the last shown string means the same visual
  /// line, so the next string is the next word; a different one is a new line.
  ///
  /// The position compared is `ctmY + textY`, not `textY` alone. Layout
  /// engines commonly wrap each block in its own `cm` translation and then
  /// start every block's text at the same text-space offset — so two different
  /// paragraphs both report `2.7` and, without the CTM, collapse into one line.
  void mark(double y, double? previous) {
    if (previous == null) return;
    if ((y - previous).abs() > 0.5) {
      pendingNewline = true;
    } else {
      pendingSpace = true;
    }
  }

  void emit(String s) {
    if (s.isEmpty) return;
    if (out.isNotEmpty) {
      if (pendingNewline) {
        out.write('\n');
      } else if (pendingSpace && !out.toString().endsWith(' ')) {
        out.write(' ');
      }
    }
    pendingNewline = false;
    pendingSpace = false;
    out.write(s);
  }

  while (i < content.length) {
    final c = content[i];

    // Literal string: (text)
    if (c == '(') {
      final literal = _readPdfLiteral(content, i);
      if (literal == null) break;
      emit(literal.value);
      i = literal.next;
      continue;
    }

    // Hex string: <ABCD> — but not a dictionary <<
    if (c == '<' && i + 1 < content.length && content[i + 1] != '<') {
      final close = content.indexOf('>', i);
      if (close < 0) break;
      emit(_decodePdfHexString(content.substring(i + 1, close)));
      i = close + 1;
      continue;
    }

    // Number operand
    if (_isNumberStart(c)) {
      final start = i;
      i++;
      while (i < content.length && _isNumberBody(content[i])) {
        i++;
      }
      final value = double.tryParse(content.substring(start, i));
      if (value != null) operands.add(value);
      continue;
    }

    // Operator token
    if (_isOperatorChar(c)) {
      final start = i;
      while (i < content.length && _isOperatorChar(content[i])) {
        i++;
      }
      final op = content.substring(start, i);

      switch (op) {
        case 'q':
          ctmStack.add(ctmY);
        case 'Q':
          if (ctmStack.isNotEmpty) ctmY = ctmStack.removeLast();
        case 'cm':
          // `a b c d e f cm` concatenates a matrix; f is its vertical
          // translation. Rotation and scale are ignored: text pages are
          // overwhelmingly upright, and only relative Y ordering is needed.
          if (operands.isNotEmpty) ctmY += operands.last;
        case 'BT':
          // A text object resets the text matrix, so the next Td is absolute.
          textY = 0;
        case 'Td':
        case 'TD':
          // `tx ty Td` is relative to the start of the current line, so the
          // running total is the absolute position. Comparing that — rather
          // than testing `ty != 0` — is what distinguishes a genuine new line
          // from the next word of the same one. Producers that wrap every word
          // in its own BT/Td emit a constant ty, which the naive test reads as
          // a line break for every single word.
          textY += operands.isNotEmpty ? operands.last : 0.0;
          mark(ctmY + textY, lastY);
          lastY = ctmY + textY;
        case 'Tm':
          // `a b c d e f Tm` sets the matrix outright; f is the vertical part.
          textY = operands.isNotEmpty ? operands.last : textY;
          mark(ctmY + textY, lastY);
          lastY = ctmY + textY;
        case 'T*':
          pendingNewline = true;
          lastY = null;
      }
      operands.clear();
      continue;
    }

    // Anything else (delimiters, whitespace) is structure we don't need.
    i++;
  }
  return out.toString();
}

bool _isNumberStart(String c) =>
    (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) || c == '-' || c == '+' || c == '.';

bool _isNumberBody(String c) =>
    (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) || c == '.' || c == '-';

bool _isOperatorChar(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '*' || c == "'" || c == '"';
}

class _PdfLiteral {
  const _PdfLiteral(this.value, this.next);
  final String value;
  final int next;
}

/// Reads a `(…)` literal starting at [start], honouring escapes and the
/// balanced nesting the format allows.
_PdfLiteral? _readPdfLiteral(String s, int start) {
  final buf = StringBuffer();
  var depth = 0;
  var i = start;

  while (i < s.length) {
    final c = s[i];
    if (c == r'\') {
      if (i + 1 >= s.length) break;
      final n = s[i + 1];
      switch (n) {
        case 'n':
          buf.write('\n');
          i += 2;
        case 'r':
          buf.write('\r');
          i += 2;
        case 't':
          buf.write('\t');
          i += 2;
        case 'b':
        case 'f':
          i += 2;
        case '(':
        case ')':
        case r'\':
          buf.write(n);
          i += 2;
        case '\n':
          i += 2; // line continuation
        default:
          if (_isOctal(n)) {
            var digits = '';
            var j = i + 1;
            while (j < s.length && digits.length < 3 && _isOctal(s[j])) {
              digits += s[j];
              j++;
            }
            buf.writeCharCode(int.parse(digits, radix: 8));
            i = j;
          } else {
            buf.write(n);
            i += 2;
          }
      }
      continue;
    }

    if (c == '(') {
      depth++;
      if (depth > 1) buf.write(c);
      i++;
      continue;
    }
    if (c == ')') {
      depth--;
      if (depth == 0) return _PdfLiteral(buf.toString(), i + 1);
      buf.write(c);
      i++;
      continue;
    }

    if (depth > 0) buf.write(c);
    i++;
  }
  return null;
}

bool _isOctal(String c) => c.length == 1 && '01234567'.contains(c);

String _decodePdfHexString(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.isEmpty) return '';
  final padded = clean.length.isEven ? clean : '${clean}0';
  final buf = StringBuffer();
  for (var i = 0; i + 1 < padded.length; i += 2) {
    final code = int.tryParse(padded.substring(i, i + 2), radix: 16);
    if (code == null) return '';
    // UTF-16BE marker used by many producers; the high byte is not a char.
    if (code == 0) continue;
    buf.writeCharCode(code);
  }
  return buf.toString();
}

// ── Quality gate ─────────────────────────────────────────────────────────

/// True when [text] plausibly reads as human language rather than as bytes
/// decoded through the wrong font encoding.
///
/// This is the guard that stops a subset-embedded-font PDF from being stored
/// as a teacher's notes. Mojibake is confident-looking: it has letters and
/// spaces, so nothing downstream would reject it. The signals that separate it
/// from prose are the proportion of ordinary printable characters, and whether
/// anything resembling real words is present.
bool looksLikeRealText(String text, {double minPrintableRatio = 0.85}) {
  final t = text.trim();
  if (t.length < 12) return false;

  var printable = 0;
  var letters = 0;
  for (final rune in t.runes) {
    final isSpace = rune == 32 || rune == 9 || rune == 10 || rune == 13;
    final isAscii = rune >= 32 && rune <= 126;
    // Latin-1 accents and common punctuation are legitimate in school notes.
    final isLatinExtra = rune >= 0xA0 && rune <= 0x24F;
    if (isSpace || isAscii || isLatinExtra) printable++;
    if ((rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122)) letters++;
  }

  if (printable / t.length < minPrintableRatio) return false;
  // Font-mapped garbage is often punctuation and symbols with few letters.
  if (letters / t.length < 0.35) return false;

  // At least a few runs that look like words, so a page of "€‰Ł‡" fails even
  // when its bytes happen to sit in a printable range.
  final words = RegExp(r'[A-Za-z]{3,}').allMatches(t).length;
  return words >= 3;
}

/// Collapses the whitespace noise every extractor produces, without destroying
/// the paragraph breaks that chunking depends on.
String normalizeExtractedText(String raw) {
  var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = t.replaceAll(' ', '');
  // Hyphenated line wrap: "photo-\nsynthesis" → "photosynthesis".
  t = t.replaceAllMapped(
    RegExp(r'([A-Za-z])-\n([a-z])'),
    (m) => '${m[1]}${m[2]}',
  );
  t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
  t = t.replaceAll(RegExp(r' *\n *'), '\n');
  // Three or more newlines is always a paragraph break, never more.
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}
