import 'dart:convert';

import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Highlights are the learner's own, per PDF: `pdf_hl_s<studentId>_<doc>`.
/// `LearnerDataWiper` removes them with the learner, by this prefix.
const kPdfHighlightPrefix = 'pdf_hl_s';

String pdfHighlightKey(int? studentId, String doc) =>
    '$kPdfHighlightPrefix${studentId ?? 0}_$doc';

/// One highlighted passage on one page. Stored as the line boxes it covers,
/// in PDF page coordinates, so it is drawn back without reloading the text.
class PdfHighlight {
  const PdfHighlight({
    required this.id,
    required this.page,
    required this.rects,
    required this.text,
  });

  final String id;
  final int page;
  final List<PdfRect> rects;
  final String text;

  bool overlaps(int otherPage, List<PdfRect> others) =>
      otherPage == page &&
      rects.any((a) => others.any((b) => _intersects(a, b)));

  Map<String, dynamic> toJson() => {
    'id': id,
    'p': page,
    't': text,
    'r': [
      for (final r in rects) [r.left, r.top, r.right, r.bottom],
    ],
  };

  static PdfHighlight? fromJson(Object? json) {
    if (json is! Map) return null;
    final page = json['p'];
    final raw = json['r'];
    if (page is! int || raw is! List) return null;
    final rects = <PdfRect>[];
    for (final r in raw) {
      if (r is! List || r.length != 4) continue;
      final v = [for (final n in r) (n as num).toDouble()];
      if (v[0] > v[2] || v[1] < v[3]) continue;
      rects.add(PdfRect(v[0], v[1], v[2], v[3]));
    }
    if (rects.isEmpty) return null;
    return PdfHighlight(
      id: '${json['id'] ?? ''}',
      page: page,
      rects: rects,
      text: '${json['t'] ?? ''}',
    );
  }
}

bool _intersects(PdfRect a, PdfRect b) =>
    a.left < b.right && b.left < a.right && a.bottom < b.top && b.bottom < a.top;

/// The line boxes a selected range covers: one box per line rather than one
/// box around the whole selection, so a highlight hugs the text.
List<PdfRect> pdfLineRects(PdfPageTextRange range) {
  final chars = range.pageText.charRects;
  final out = <PdfRect>[];
  PdfRect? line;
  for (var i = range.start; i < range.end && i < chars.length; i++) {
    final r = chars[i];
    if (r.width <= 0 || r.height <= 0) continue; // line breaks
    if (line == null) {
      line = r;
      continue;
    }
    final mid = (r.top + r.bottom) / 2;
    if (mid <= line.top && mid >= line.bottom) {
      line = line.merge(r);
    } else {
      out.add(line);
      line = r;
    }
  }
  if (line != null) out.add(line);
  return out;
}

List<PdfHighlight> loadPdfHighlights(SharedPreferences? prefs, String key) {
  final raw = prefs?.getString(key);
  if (raw == null) return [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return [
      for (final j in list)
        if (PdfHighlight.fromJson(j) case final h?) h,
    ];
  } catch (_) {
    return [];
  }
}

Future<void> savePdfHighlights(
  SharedPreferences? prefs,
  String key,
  List<PdfHighlight> highlights,
) async {
  if (prefs == null) return;
  if (highlights.isEmpty) {
    await prefs.remove(key);
  } else {
    await prefs.setString(
      key,
      jsonEncode([for (final h in highlights) h.toJson()]),
    );
  }
}
