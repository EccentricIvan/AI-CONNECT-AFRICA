import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'quick_style_edit.dart';

/// Page colours taken from a picture — "use the colours of this photo" —
/// worked out offline from its pixels, since the coder model can't see
/// images. Null when the bytes aren't a readable picture.
///
/// The picture's most common vivid colour becomes the accent (buttons,
/// links), a deep shade of it the top bar and headings, and a pale tint of
/// it the page background, so the page reads well whatever the photo is.
QuickStyle? paletteStyleFromImageBytes(Uint8List bytes) {
  // decodeImage throws, rather than returning null, on bytes it can't read
  // (an SVG logo, a damaged file).
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final small = decoded.width > 64
      ? img.copyResize(decoded, width: 64)
      : decoded;

  final buckets = <int, _Bucket>{};
  for (final p in small) {
    if (p.a < 128) continue;
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
    (buckets[key] ??= _Bucket()).add(r, g, b);
  }
  if (buckets.isEmpty) return null;

  final colours = buckets.values.map((b) => b.average).toList();
  _Rgb? accent;
  var best = 0.0;
  for (final c in colours) {
    final (s, l) = (c.saturation, c.lightness);
    if (s < 0.25 || l < 0.18 || l > 0.85) continue;
    final score = c.count * (0.5 + s);
    if (score > best) {
      best = score;
      accent = c;
    }
  }
  // A black-and-white or washed-out picture: use its most common mid tone.
  accent ??= colours
      .where((c) => c.lightness > 0.15 && c.lightness < 0.85)
      .fold<_Rgb?>(null, (a, c) => a == null || c.count > a.count ? c : a);
  accent ??= colours.reduce((a, c) => c.count > a.count ? c : a);

  final deep = accent.mix(
    const _Rgb(0, 0, 0),
    accent.lightness > 0.5 ? 0.55 : 0.35,
  );
  final pale = accent.mix(const _Rgb(255, 255, 255), 0.92);
  return QuickStyle(
    accentColor: accent.hex,
    barColor: deep.hex,
    headingColor: deep.hex,
    backgroundColor: pale.hex,
    textColor: '#1f2937',
  );
}

class _Bucket {
  int n = 0, r = 0, g = 0, b = 0;
  void add(int rr, int gg, int bb) {
    n++;
    r += rr;
    g += gg;
    b += bb;
  }

  _Rgb get average => _Rgb(r ~/ n, g ~/ n, b ~/ n, count: n);
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b, {this.count = 0});
  final int r, g, b, count;

  double get _max => [r, g, b].reduce((a, c) => a > c ? a : c) / 255;
  double get _min => [r, g, b].reduce((a, c) => a < c ? a : c) / 255;
  double get lightness => (_max + _min) / 2;
  double get saturation {
    final d = _max - _min;
    if (d == 0) return 0;
    return d / (1 - (2 * lightness - 1).abs());
  }

  _Rgb mix(_Rgb other, double t) => _Rgb(
    (r + (other.r - r) * t).round(),
    (g + (other.g - g) * t).round(),
    (b + (other.b - b) * t).round(),
  );

  String get hex =>
      '#${[r, g, b].map((c) => c.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}';
}
