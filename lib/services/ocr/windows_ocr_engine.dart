import 'package:flutter/services.dart';

import 'ocr_engine.dart';

/// Windows: the built-in `Windows.Media.Ocr` engine (Windows 10+, offline),
/// reached through the `otic/ocr` channel in `windows/runner/ocr_channel.cpp`.
class WindowsOcrEngine extends OcrEngine {
  WindowsOcrEngine._(this.maxDimension);

  static const _channel = MethodChannel('otic/ocr');

  @override
  final int maxDimension;

  /// Null when no OCR language is installed on this PC.
  static Future<WindowsOcrEngine?> create() async {
    final info = await _channel.invokeMapMethod<String, Object?>('info');
    if (info == null || info['language'] == null) return null;
    return WindowsOcrEngine._((info['maxDimension'] as int?) ?? 2600);
  }

  @override
  Future<OcrResult> recognize(RenderedPage page) async {
    final raw = await _channel.invokeListMethod<Object?>('recognize', {
      'bgra': page.bgra,
      'width': page.width,
      'height': page.height,
    });
    final lines = <OcrLine>[
      for (final item in raw ?? const [])
        if (item is Map)
          OcrLine(
            (item['text'] as String?) ?? '',
            (item['left'] as num).toDouble(),
            (item['top'] as num).toDouble(),
            (item['width'] as num).toDouble(),
            (item['height'] as num).toDouble(),
          ),
    ]..sort((a, b) => a.top.compareTo(b.top));
    return OcrResult(lines);
  }
}
