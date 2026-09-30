import 'dart:math' as math;

import '../ocr/ocr_engine.dart';

/// A diagram the tutor can't see, recorded in a note as a marker paragraph so
/// it travels with the text (search index, class sync) and can be turned into
/// "look at page N" for the student.
class DiagramMarker {
  const DiagramMarker({
    required this.caption,
    required this.page,
    required this.document,
  });

  /// "Figure 3.2 The human heart", or "Diagram" when it had no caption.
  final String caption;

  /// PDF page number (1-based) — not always the number printed on the page.
  final int page;
  final String document;

  bool get hasCaption => caption != kUncaptioned;

  static const kUncaptioned = 'Diagram';

  static final _pattern = RegExp(
    r'\[DIAGRAM: ([^|\]]+) \| page (\d+) of the PDF "([^"\]]*)"\]',
  );

  String format() =>
      '[DIAGRAM: ${_clean(caption)} | page $page of the PDF "${_clean(document)}"]';

  /// Every marker in [text], in order.
  static List<DiagramMarker> parseAll(String text) => [
    for (final m in _pattern.allMatches(text))
      DiagramMarker(
        caption: m[1]!.trim(),
        page: int.parse(m[2]!),
        document: m[3]!.trim(),
      ),
  ];

  /// Start/end offsets of every marker in [text].
  static Iterable<(int, int)> spans(String text) =>
      _pattern.allMatches(text).map((m) => (m.start, m.end));

  /// What the student is told. Leads with the caption, since that's what
  /// finds the diagram in a printed book whose page numbers differ.
  String pointer() {
    final what = hasCaption ? caption : 'the diagram';
    return 'Diagram: see $what, page $page of the PDF "$document". '
        'Open the PDF on your phone or look in the printed copy.';
  }

  String get key => '$document|$page|$caption';

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'[\[\]|"\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True for lines that are diagram markers, so heading detection skips them.
bool isDiagramMarkerLine(String line) => line.trimLeft().startsWith('[DIAGRAM: ');

final _captionStart = RegExp(
  r'^(fig(?:ure)?\.?|diagram|illustration|chart|graph|map|plate)\s*'
  r'(\d+(?:\.\d+)*[a-z]?)\b\s*[:.\-–—]?\s*(.*)$',
  caseSensitive: false,
);

// "Figure 3 shows the heart." is a reference in the prose, not a caption.
final _referenceVerb = RegExp(
  r'^(shows?|illustrates?|is|are|was|were|below|above|represents?|gives?|'
  r'describes?|explains?|and|of|in|on)\b',
  caseSensitive: false,
);

/// The caption [line] names, or null if it isn't a caption.
String? captionOf(String line) {
  final t = line.trim();
  if (t.isEmpty || t.length > 120) return null;
  final m = _captionStart.firstMatch(t);
  if (m == null) return null;
  final rest = m[3]!.trim();
  if (_referenceVerb.hasMatch(rest)) return null;
  final label = '${_titleCase(m[1]!)} ${m[2]}';
  final title = rest.replaceAll(RegExp(r'[.:;,\s]+$'), '');
  return title.isEmpty ? label : '$label $title';
}

String _titleCase(String word) {
  final w = word.toLowerCase();
  if (w.startsWith('fig')) return 'Figure';
  return w[0].toUpperCase() + w.substring(1);
}

/// [text] for one page with each caption line replaced by its marker, and an
/// uncaptioned marker added when [hasPicture] but no caption was found.
({String text, int diagrams}) annotatePage(
  String text, {
  required int page,
  required String document,
  required bool hasPicture,
}) {
  final out = <String>[];
  var diagrams = 0;
  for (final line in text.split('\n')) {
    final caption = captionOf(line);
    if (caption == null) {
      out.add(line);
      continue;
    }
    diagrams++;
    out.add(
      '\n${DiagramMarker(caption: caption, page: page, document: document).format()}\n',
    );
  }
  if (diagrams == 0 && hasPicture) {
    diagrams = 1;
    out.add(
      '\n${DiagramMarker(caption: DiagramMarker.kUncaptioned, page: page, document: document).format()}',
    );
  }
  return (text: out.join('\n'), diagrams: diagrams);
}

/// A box on the page as fractions of its width/height, top-left origin.
class PageBox {
  const PageBox(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Fraction of sampled pixels that are dark. A blank page is well under 0.005.
double inkRatio(RenderedPage page) {
  final stride = math.max(1, page.width ~/ 200);
  var dark = 0, seen = 0;
  for (var y = 0; y < page.height; y += stride) {
    for (var x = 0; x < page.width; x += stride) {
      final i = (y * page.width + x) * 4;
      final luma = 0.114 * page.bgra[i] + 0.587 * page.bgra[i + 1] + 0.299 * page.bgra[i + 2];
      if (luma < 140) dark++;
      seen++;
    }
  }
  return seen == 0 ? 0 : dark / seen;
}

/// Number of picture-like regions on [page]: areas with ink that no text box
/// covers, big enough to be a diagram rather than a rule, a smudge or the
/// scanner's edge shadow.
int countPictureRegions(RenderedPage page, List<PageBox> textBoxes) {
  const cols = 48;
  final cell = page.width / cols;
  final rows = (page.height / cell).ceil();
  if (rows == 0) return 0;

  final isText = List.filled(cols * rows, false);
  for (final b in textBoxes) {
    final c0 = ((b.left * page.width) / cell - 0.5).floor().clamp(0, cols - 1);
    final c1 = ((b.right * page.width) / cell + 0.5).floor().clamp(0, cols - 1);
    final r0 = ((b.top * page.height) / cell - 0.5).floor().clamp(0, rows - 1);
    final r1 = ((b.bottom * page.height) / cell + 0.5).floor().clamp(0, rows - 1);
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        isText[r * cols + c] = true;
      }
    }
  }

  final marginC = (cols * 0.05).ceil();
  final marginR = (rows * 0.05).ceil();
  final stride = (cell / 6).floor().clamp(1, 1 << 20);
  final ink = List.filled(cols * rows, false);
  for (var r = marginR; r < rows - marginR; r++) {
    for (var c = marginC; c < cols - marginC; c++) {
      if (isText[r * cols + c]) continue;
      final x0 = (c * cell).floor(), x1 = ((c + 1) * cell).floor().clamp(0, page.width);
      final y0 = (r * cell).floor(), y1 = ((r + 1) * cell).floor().clamp(0, page.height);
      var dark = 0, seen = 0;
      for (var y = y0; y < y1; y += stride) {
        for (var x = x0; x < x1; x += stride) {
          final i = (y * page.width + x) * 4;
          final luma = 0.114 * page.bgra[i] +
              0.587 * page.bgra[i + 1] +
              0.299 * page.bgra[i + 2];
          if (luma < 140) dark++;
          seen++;
        }
      }
      ink[r * cols + c] = seen > 0 && dark / seen >= 0.03;
    }
  }

  var regions = 0;
  final visited = List.filled(cols * rows, false);
  for (var start = 0; start < ink.length; start++) {
    if (!ink[start] || visited[start]) continue;
    var minC = cols, maxC = 0, minR = rows, maxR = 0, count = 0;
    final stack = [start];
    visited[start] = true;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final r = i ~/ cols, c = i % cols;
      count++;
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final nr = r + dr, nc = c + dc;
          if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
          final n = nr * cols + nc;
          if (ink[n] && !visited[n]) {
            visited[n] = true;
            stack.add(n);
          }
        }
      }
    }
    final wide = (maxC - minC + 1) >= cols * 0.15;
    final tall = (maxR - minR + 1) >= rows * 0.08;
    if (wide && tall && count >= 12) regions++;
  }
  return regions;
}
