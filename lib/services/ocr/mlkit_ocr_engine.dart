import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ocr_engine.dart';

/// Android: Google ML Kit with the Latin model bundled in the APK
/// (`com.google.mlkit:text-recognition`), so nothing is downloaded.
class MlKitOcrEngine extends OcrEngine {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  int get maxDimension => 2400;

  @override
  Future<OcrResult> recognize(RenderedPage page) async {
    // ML Kit takes raw bytes only as NV21/YV12 camera frames, not RGBA, so
    // the page goes through a temporary PNG.
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'otic_ocr_${DateTime.now().microsecondsSinceEpoch}.png'),
    );
    try {
      await file.writeAsBytes(await encodePng(page), flush: true);
      final result = await _recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      final lines = [
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrLine(
              line.text,
              line.boundingBox.left,
              line.boundingBox.top,
              line.boundingBox.width,
              line.boundingBox.height,
            ),
      ]..sort((a, b) => a.top.compareTo(b.top));
      return OcrResult(lines);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
