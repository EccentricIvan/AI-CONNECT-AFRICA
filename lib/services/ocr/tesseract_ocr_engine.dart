import 'dart:io';

import 'package:path/path.dart' as p;

import 'ocr_engine.dart';

/// Linux: the system `tesseract` command, when installed. There is no
/// bundled engine for Linux, the smallest target.
class TesseractOcrEngine extends OcrEngine {
  TesseractOcrEngine._();

  /// Null when `tesseract` isn't on the PATH.
  static Future<TesseractOcrEngine?> create() async {
    try {
      final r = await Process.run('tesseract', ['--version']);
      return r.exitCode == 0 ? TesseractOcrEngine._() : null;
    } on ProcessException {
      return null;
    }
  }

  @override
  int get maxDimension => 3000;

  @override
  Future<OcrResult> recognize(RenderedPage page) async {
    final dir = await Directory.systemTemp.createTemp('otic_ocr');
    try {
      final png = File(p.join(dir.path, 'page.png'));
      await png.writeAsBytes(await encodePng(page), flush: true);
      final r = await Process.run('tesseract', [png.path, 'stdout', 'tsv']);
      if (r.exitCode != 0) return const OcrResult([]);
      return OcrResult(parseTesseractTsv(r.stdout as String));
    } finally {
      await dir.delete(recursive: true);
    }
  }
}

/// Groups tesseract's word rows (level 5) into lines with bounding boxes.
List<OcrLine> parseTesseractTsv(String tsv) {
  final words = <String, List<List<String>>>{};
  for (final row in tsv.split('\n').skip(1)) {
    final c = row.split('\t');
    if (c.length < 12 || c[0] != '5' || c[11].trim().isEmpty) continue;
    words.putIfAbsent('${c[2]}-${c[3]}-${c[4]}', () => []).add(c);
  }
  final lines = <OcrLine>[];
  for (final group in words.values) {
    var left = double.infinity, top = double.infinity;
    var right = 0.0, bottom = 0.0;
    for (final c in group) {
      final l = double.parse(c[6]), t = double.parse(c[7]);
      final w = double.parse(c[8]), h = double.parse(c[9]);
      if (l < left) left = l;
      if (t < top) top = t;
      if (l + w > right) right = l + w;
      if (t + h > bottom) bottom = t + h;
    }
    lines.add(OcrLine(
      group.map((c) => c[11].trim()).join(' '),
      left,
      top,
      right - left,
      bottom - top,
    ));
  }
  return lines..sort((a, b) => a.top.compareTo(b.top));
}
