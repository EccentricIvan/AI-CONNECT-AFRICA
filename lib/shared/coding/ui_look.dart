import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'quick_style_edit.dart';

/// "Make the UI like this" for a screenshot, worked out offline from the
/// pixels — the coder model can't see images. It measures the look (light
/// or dark, colours, top bar, card colour, corner roundness, columns of
/// cards) and restyles the learner's page to match. It does not copy the
/// screenshot's layout or fonts.
class UiLook {
  const UiLook({
    required this.dark,
    required this.background,
    required this.bar,
    required this.surface,
    required this.cards,
    required this.radius,
    required this.columns,
    this.accent,
  });

  final bool dark;
  final String background;

  /// Top bar / navigation colour (the background itself for a flat header).
  final String bar;

  /// Card colour; the background when the screenshot has no visible cards.
  final String surface;
  final bool cards;

  /// Corner radius in CSS px.
  final int radius;

  /// Cards per row on a wide screen; 0 or 1 leaves the page's own layout.
  final int columns;
  final String? accent;

  String get text => dark ? '#e5e7eb' : '#1f2937';
  String get heading => dark ? '#f9fafb' : '#111827';

  /// What was matched, for the "applied" message.
  List<String> describe() => [
    dark ? 'dark theme' : 'light theme',
    if (cards)
      radius >= 20
          ? 'very rounded cards'
          : radius >= 8
          ? 'rounded cards'
          : 'square cards',
    if (columns >= 2) '$columns cards per row',
    if (accent != null) 'accent $accent',
  ];

  Map<String, Object?> toJson() => {
    'dark': dark,
    'background': background,
    'bar': bar,
    'surface': surface,
    'cards': cards,
    'radius': radius,
    'columns': columns,
    if (accent != null) 'accent': accent,
  };
}

final _lookRequestRe = RegExp(
  r'(like this|like the (picture|image|screenshot|photo)|same (style|look|design|ui|theme)|'
  r'this (style|design|look|ui|theme|layout)|(copy|match|follow) (this|the) '
  r'(design|style|ui|look|layout|theme)|(look|style|design)s? like)',
);

/// "Make the UI like this", "same style as this", "copy this design"…
bool isLookRequest(String instruction) =>
    _lookRequestRe.hasMatch(instruction.toLowerCase());

// ── Measuring the screenshot ──────────────────────────────────────────────

/// Null when [bytes] isn't a readable picture.
UiLook? analyzeUiScreenshot(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final shot = img.bakeOrientation(decoded);
  final portrait = shot.height > shot.width;
  const w = 160;
  final small = img.copyResize(
    shot,
    width: w,
    interpolation: img.Interpolation.average,
  );
  final h = small.height;
  if (h < 8) return null;

  final px = List<_C>.generate(w * h, (i) {
    final p = small.getPixel(i % w, i ~/ w);
    return _C(p.r.toInt(), p.g.toInt(), p.b.toInt());
  });
  _C at(int x, int y) => px[y * w + x];

  final band = math.max(3, (h * 0.08).round());

  // The page background is what shows in the gutters: the right edge and
  // the bottom rows. Not the most common colour overall — on a dashboard
  // the cards often cover more of the screen than the background does, and
  // a left sidebar would fool a left-edge sample.
  final edges = [
    for (var y = band; y < h; y++)
      for (var x = w - 3; x < w; x++) at(x, y),
    for (var y = h - 3; y < h; y++)
      for (var x = 0; x < w - 3; x++) at(x, y),
  ];
  final background = _dominant(edges)!;

  // Top bar: a band of one colour across the top that isn't the background.
  final top = [
    for (var y = 0; y < band; y++)
      for (var x = 0; x < w; x++) at(x, y),
  ];
  final topColour = _dominant(top)!;
  var bar = background;
  if (topColour.distance(background) > 40 && _share(top, topColour) > 0.5) {
    bar = topColour;
  } else {
    // No top bar — a side bar's colour stands in for the navigation.
    final side = [
      for (var y = band; y < h; y++)
        for (var x = 0; x < (w * 0.15).round(); x++) at(x, y),
    ];
    final sideColour = _dominant(side)!;
    if (sideColour.distance(background) > 40 &&
        _share(side, sideColour) > 0.6) {
      bar = sideColour;
    }
  }

  // Cards: a large, calm colour that is neither the background nor the bar.
  final ranked = _ranked(px);
  _C? surface;
  for (final c in ranked) {
    if (c.count < px.length * 0.04) break;
    if (c.distance(background) < 24 || c.distance(bar) < 24) continue;
    if (c.saturation > 0.35) continue;
    surface = c;
    break;
  }

  var radius = 0;
  var columns = 0;
  var cards = false;
  if (surface != null) {
    final boxes = _components(px, w, h, surface);
    cards = boxes.length >= 2;
    if (cards) {
      // Diagonal gap at a box corner ≈ r·(1 − 1/√2).
      final gaps = <double>[];
      for (final b in boxes) {
        gaps.add(_cornerGap(px, w, surface, b.x0, b.y0, 1, 1).toDouble());
        gaps.add(_cornerGap(px, w, surface, b.x1, b.y0, -1, 1).toDouble());
      }
      gaps.sort();
      final gap = gaps[gaps.length ~/ 2];
      final cssWidth = portrait ? 400 : 1280;
      final r = gap / (1 - 1 / math.sqrt2) * cssWidth / w;
      radius = ((r / 6).round() * 6).clamp(0, 28).toInt();
      columns = _columns(boxes).clamp(1, 4).toInt();
    }
  }

  // Accent: the most used vivid colour that isn't a surface.
  _C? accent;
  for (final c in ranked) {
    if (c.saturation < 0.35 || c.lightness < 0.2 || c.lightness > 0.8) continue;
    if (c.distance(background) < 30) continue;
    if (surface != null && c.distance(surface) < 30) continue;
    accent = c;
    break;
  }
  if (accent == null && bar.saturation >= 0.35) accent = bar;

  return UiLook(
    dark: background.luminance < 0.3,
    background: background.hex,
    bar: bar.hex,
    surface: (surface ?? background).hex,
    cards: cards,
    radius: radius,
    columns: columns,
    accent: accent?.hex,
  );
}

class _C {
  const _C(this.r, this.g, this.b, {this.count = 0});
  final int r, g, b, count;

  int get key => (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);

  double distance(_C o) {
    final dr = r - o.r, dg = g - o.g, db = b - o.b;
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  double get _max => math.max(r, math.max(g, b)) / 255;
  double get _min => math.min(r, math.min(g, b)) / 255;
  double get lightness => (_max + _min) / 2;
  double get saturation {
    final d = _max - _min;
    if (d == 0) return 0;
    return d / (1 - (2 * lightness - 1).abs());
  }

  double get luminance => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;

  String get hex =>
      '#${[r, g, b].map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';
}

/// Colours by how many pixels share them, most common first.
List<_C> _ranked(List<_C> px) {
  final sums = <int, List<int>>{};
  for (final c in px) {
    final s = sums[c.key] ??= [0, 0, 0, 0];
    s[0]++;
    s[1] += c.r;
    s[2] += c.g;
    s[3] += c.b;
  }
  final out = [
    for (final s in sums.values)
      _C(s[1] ~/ s[0], s[2] ~/ s[0], s[3] ~/ s[0], count: s[0]),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return out;
}

_C? _dominant(List<_C> px) => px.isEmpty ? null : _ranked(px).first;

double _share(List<_C> px, _C colour) =>
    px.where((c) => c.distance(colour) < 24).length / px.length;

typedef _Box = ({int x0, int y0, int x1, int y1, int area});

/// Solid blocks of [surface] big enough to be cards.
List<_Box> _components(List<_C> px, int w, int h, _C surface) {
  final mask = List<bool>.generate(
    px.length,
    (i) => px[i].distance(surface) < 20,
  );
  final seen = List<bool>.filled(px.length, false);
  final boxes = <_Box>[];
  final minArea = px.length * 0.006;
  for (var i = 0; i < px.length; i++) {
    if (!mask[i] || seen[i]) continue;
    var x0 = w, y0 = h, x1 = 0, y1 = 0, area = 0;
    final stack = [i];
    seen[i] = true;
    while (stack.isNotEmpty) {
      final j = stack.removeLast();
      final x = j % w, y = j ~/ w;
      area++;
      x0 = math.min(x0, x);
      x1 = math.max(x1, x);
      y0 = math.min(y0, y);
      y1 = math.max(y1, y);
      for (final n in [
        if (x > 0) j - 1,
        if (x < w - 1) j + 1,
        if (y > 0) j - w,
        if (y < h - 1) j + w,
      ]) {
        if (mask[n] && !seen[n]) {
          seen[n] = true;
          stack.add(n);
        }
      }
    }
    final bw = x1 - x0 + 1;
    // A block spanning (nearly) the whole width is a band, not a card.
    if (area >= minArea && bw >= w * 0.08 && bw < w * 0.97) {
      boxes.add((x0: x0, y0: y0, x1: x1, y1: y1, area: area));
    }
    if (boxes.length >= 40) break;
  }
  return boxes;
}

/// Steps along the diagonal from a box corner until the card colour starts.
int _cornerGap(List<_C> px, int w, _C surface, int x, int y, int dx, int dy) {
  final h = px.length ~/ w;
  for (var i = 0; i < 8; i++) {
    final cx = x + dx * i, cy = y + dy * i;
    if (cx < 0 || cx >= w || cy < 0 || cy >= h) return i;
    if (px[cy * w + cx].distance(surface) < 20) return i;
  }
  return 8;
}

/// Most similar-sized cards side by side in one row.
int _columns(List<_Box> boxes) {
  var best = 1;
  for (final a in boxes) {
    final aw = a.x1 - a.x0, ac = (a.y0 + a.y1) / 2;
    var n = 0;
    for (final b in boxes) {
      final bw = b.x1 - b.x0;
      if (ac < b.y0 || ac > b.y1) continue;
      if ((bw - aw).abs() > aw * 0.35) continue;
      n++;
    }
    best = math.max(best, n);
  }
  return best;
}

// ── Restyling the page ────────────────────────────────────────────────────

const _cardSel =
    '.card,.tile,.panel,.box,.cbox,.mcard,.listing,'
    '[class*="-card"],[class*="-item"],[class*="__item"]';
const _gridSel =
    '.grid,.tiles,.cards,.cols,.listings,.mgrid,'
    '[class*="-grid"],[class*="grid--"]';
// Hero/banner sections keep their own colour or photo.
const _sectionSel =
    'main,section:not([class*="hero"]):not([class*="banner"]),'
    '.section:not([class*="hero"])';

final _lookBlockRe = RegExp(
  r'<style id="otic-look">[\s\S]*?</style>\s*',
  caseSensitive: false,
);

/// Restyles [html] to [look]. Colours go through the Style panel's own block
/// (so it shows them); shape and layout go in one `otic-look` block that a
/// second "like this" replaces rather than stacks.
String applyUiLook(String html, UiLook look) {
  final colours = QuickStyle(
    backgroundColor: look.background,
    textColor: look.text,
    headingColor: look.heading,
    barColor: look.bar,
    accentColor: look.accent,
  );
  var out = applyQuickStyle(html, readQuickStyle(html).merge(colours));

  final r = look.radius;
  final css = StringBuffer()
    ..writeln('<style id="otic-look">')
    ..writeln('/* otic-look ${jsonEncode(look.toJson())} */')
    ..writeln('$_sectionSel{background-color:${look.background} !important}');
  if (look.cards) {
    final border = look.dark ? 'rgba(255,255,255,.08)' : 'rgba(15,23,42,.08)';
    final shadow = look.dark ? 'none' : '0 6px 18px rgba(15,23,42,.08)';
    css.writeln(
      '$_cardSel{background-color:${look.surface} !important;'
      'border-radius:${r}px !important;border:1px solid $border !important;'
      'box-shadow:$shadow !important}',
    );
  }
  final control = r >= 20 ? '999px' : '${r}px';
  css.writeln(
    'button,.btn,[class*="btn"],input,select,textarea'
    '{border-radius:$control !important}',
  );
  if (look.columns >= 2) {
    final phone = math.min(look.columns, 2);
    css
      ..writeln(
        '@media (min-width:700px){$_gridSel{display:grid !important;'
        'grid-template-columns:repeat(${look.columns},minmax(0,1fr)) !important;'
        'gap:16px !important}}',
      )
      ..writeln(
        '@media (max-width:699px){$_gridSel{display:grid !important;'
        'grid-template-columns:repeat($phone,minmax(0,1fr)) !important;'
        'gap:12px !important}}',
      );
  }
  css.write('</style>\n');

  out = out.replaceAll(_lookBlockRe, '');
  final i = out.toLowerCase().lastIndexOf('</head>');
  if (i < 0) return '$css$out';
  return '${out.substring(0, i)}$css${out.substring(i)}';
}
