import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mlkit_ocr_engine.dart';
import 'tesseract_ocr_engine.dart';
import 'windows_ocr_engine.dart';

/// One PDF page rendered to pixels, top-left origin.
class RenderedPage {
  const RenderedPage({
    required this.bgra,
    required this.width,
    required this.height,
  });

  /// BGRA8888, `width * height * 4` bytes.
  final Uint8List bgra;
  final int width;
  final int height;
}

/// A line of recognised text and where it sits on the rendered page, in
/// pixels, top-left origin.
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.width, this.height);

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
}

class OcrResult {
  const OcrResult(this.lines);

  /// Reading order, top to bottom.
  final List<OcrLine> lines;

  String get text => lines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join('\n');
}

/// On-device text recognition for scanned PDF pages. Every implementation
/// runs with the network off; none downloads a model at runtime.
abstract class OcrEngine {
  /// Largest width or height the engine accepts, in pixels.
  int get maxDimension;

  Future<OcrResult> recognize(RenderedPage page);

  Future<void> dispose() async {}
}

/// PNG bytes for [page], via the engine's native encoder (much faster than a
/// pure-Dart encoder on a 2000 px page).
Future<Uint8List> encodePng(RenderedPage page) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(page.bgra);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: page.width,
    height: page.height,
    pixelFormat: ui.PixelFormat.bgra8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// This device's OCR engine, or null when scanned pages can't be read here
/// (web, Linux without tesseract, Windows without an OCR language).
final ocrEngineProvider = FutureProvider<OcrEngine?>((ref) async {
  if (kIsWeb) return null;
  final OcrEngine? engine;
  try {
    if (Platform.isAndroid) {
      engine = MlKitOcrEngine();
    } else if (Platform.isWindows) {
      engine = await WindowsOcrEngine.create();
    } else if (Platform.isLinux) {
      engine = await TesseractOcrEngine.create();
    } else {
      engine = null;
    }
  } catch (e) {
    debugPrint('OCR unavailable: $e');
    return null;
  }
  ref.onDispose(() => engine?.dispose());
  return engine;
});

/// Why scanned pages can't be read on this device, for the teacher.
String ocrUnavailableReason() {
  if (!kIsWeb && Platform.isLinux) {
    return 'Scanned pages need the tesseract-ocr package on this computer '
        '(sudo apt install tesseract-ocr).';
  }
  if (!kIsWeb && Platform.isWindows) {
    return 'Scanned pages need a Windows OCR language. Add English in '
        'Settings → Time & language → Language.';
  }
  return 'Scanned pages cannot be read on this device.';
}
