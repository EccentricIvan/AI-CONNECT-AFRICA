import 'dart:convert';
import 'dart:math' show pow;

/// Instant, model-free look changes for a built page: text / heading /
/// background / accent colours, font family and text size.
///
/// Everything lives in one `<style id="otic-style">` block the page carries
/// with it, so a change is exact, immediate and repeatable ("make the text
/// red" twice gives the same page), and the settings round-trip through a
/// JSON comment so the Style panel can show what is already applied. The
/// coder model is only used for requests this cannot express.
class QuickStyle {
  const QuickStyle({
    this.textColor,
    this.headingColor,
    this.backgroundColor,
    this.accentColor,
    this.barColor,
    this.fontFamily,
    this.fontScale,
  });

  final String? textColor;
  final String? headingColor;
  final String? backgroundColor;

  /// Buttons, links and the template's `--primary` colour.
  final String? accentColor;

  /// Top bar / navigation background.
  final String? barColor;

  /// One of [kQuickFonts]' keys.
  final String? fontFamily;

  /// 1.0 = template default.
  final double? fontScale;

  bool get isEmpty =>
      textColor == null &&
      headingColor == null &&
      backgroundColor == null &&
      accentColor == null &&
      barColor == null &&
      fontFamily == null &&
      (fontScale == null || fontScale == 1.0);

  /// [other]'s set values win.
  QuickStyle merge(QuickStyle other) => QuickStyle(
        textColor: other.textColor ?? textColor,
        headingColor: other.headingColor ?? headingColor,
        backgroundColor: other.backgroundColor ?? backgroundColor,
        accentColor: other.accentColor ?? accentColor,
        barColor: other.barColor ?? barColor,
        fontFamily: other.fontFamily ?? fontFamily,
        fontScale: other.fontScale ?? fontScale,
      );

  Map<String, Object?> toJson() => {
        if (textColor != null) 'text': textColor,
        if (headingColor != null) 'heading': headingColor,
        if (backgroundColor != null) 'background': backgroundColor,
        if (accentColor != null) 'accent': accentColor,
        if (barColor != null) 'bar': barColor,
        if (fontFamily != null) 'font': fontFamily,
        if (fontScale != null) 'scale': fontScale,
      };

  static QuickStyle fromJson(Map<String, Object?> j) => QuickStyle(
        textColor: _color(j['text']),
        headingColor: _color(j['heading']),
        backgroundColor: _color(j['background']),
        accentColor: _color(j['accent']),
        barColor: _color(j['bar']),
        fontFamily: kQuickFonts.containsKey(j['font']) ? j['font'] as String : null,
        fontScale: j['scale'] is num
            ? (j['scale'] as num).toDouble().clamp(0.7, 1.6)
            : null,
      );

  static String? _color(Object? v) => v is String ? normalizeCssColor(v) : null;

  /// Human summary for the "applied" snackbar.
  String describe() {
    final parts = <String>[
      if (textColor != null) 'text $textColor',
      if (headingColor != null) 'headings $headingColor',
      if (backgroundColor != null) 'background $backgroundColor',
      if (accentColor != null) 'buttons & links $accentColor',
      if (barColor != null) 'top bar $barColor',
      if (fontFamily != null) '${kQuickFonts[fontFamily]!.label} font',
      if (fontScale != null && fontScale != 1.0)
        'text size ${(fontScale! * 100).round()}%',
    ];
    return parts.join(', ');
  }
}

class QuickFont {
  const QuickFont(this.label, this.stack);
  final String label;
  final String stack;
}

/// System font stacks only — nothing downloads, the page stays offline.
const kQuickFonts = <String, QuickFont>{
  'modern': QuickFont('Modern', 'Inter, "Segoe UI", Roboto, system-ui, sans-serif'),
  'classic': QuickFont('Classic', 'Georgia, "Times New Roman", serif'),
  'rounded': QuickFont('Rounded', '"Trebuchet MS", "Verdana", sans-serif'),
  'code': QuickFont('Typewriter', '"Courier New", Consolas, monospace'),
  'handwriting': QuickFont('Handwriting', '"Comic Sans MS", "Segoe Print", cursive'),
};

/// Named colours students actually type, including a few local spellings.
const kQuickColors = <String, String>{
  'red': '#dc2626',
  'dark red': '#991b1b',
  'maroon': '#7f1d1d',
  'orange': '#ea580c',
  'yellow': '#eab308',
  'gold': '#ca8a04',
  'green': '#16a34a',
  'dark green': '#166534',
  'light green': '#86efac',
  'lime': '#65a30d',
  'teal': '#0d9488',
  'cyan': '#0891b2',
  'blue': '#2563eb',
  'light blue': '#93c5fd',
  'sky blue': '#0ea5e9',
  'dark blue': '#1e3a8a',
  'navy': '#1e3a8a',
  'navy blue': '#1e3a8a',
  'purple': '#7c3aed',
  'violet': '#8b5cf6',
  'pink': '#db2777',
  'light pink': '#fbcfe8',
  'brown': '#92400e',
  'black': '#111827',
  'white': '#ffffff',
  'grey': '#6b7280',
  'gray': '#6b7280',
  'light grey': '#e5e7eb',
  'light gray': '#e5e7eb',
  'dark grey': '#374151',
  'dark gray': '#374151',
  'cream': '#fef3c7',
  'beige': '#f5f5dc',
  'silver': '#cbd5e1',
};

final _hexRe = RegExp(r'#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b');

/// Safe CSS colour from a name or hex, else null. Never returns anything
/// that could break out of a CSS declaration.
String? normalizeCssColor(String raw) {
  final v = raw.trim().toLowerCase();
  if (_hexRe.hasMatch(v) && _hexRe.firstMatch(v)!.group(0)!.length == v.length) {
    return v;
  }
  return kQuickColors[v];
}

/// Finds a colour inside free text ("make the text dark blue").
String? _findColor(String text) {
  final hex = _hexRe.firstMatch(text);
  if (hex != null) return hex.group(0)!.toLowerCase();
  // Longest names first so "dark blue" wins over "blue".
  final names = kQuickColors.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final n in names) {
    if (RegExp('\\b${RegExp.escape(n)}\\b').hasMatch(text)) return kQuickColors[n];
  }
  return null;
}

/// Turns a plain-language request into a style change, or null when the
/// request is about something else (layout, new sections…) and should go to
/// the coder model instead.
///
/// [current] is the page's existing style, for relative changes like
/// "make the text bigger".
QuickStyle? parseQuickStyleRequest(String request, {QuickStyle current = const QuickStyle()}) {
  final t = request.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;

  // Size.
  final bigger = RegExp(r'\b(bigger|larger|increase|enlarge)\b').hasMatch(t);
  final smaller = RegExp(r'\b(smaller|decrease|reduce|tiny)\b').hasMatch(t);
  final aboutText = RegExp(r'\b(text|font|words|writing|letters|size)\b').hasMatch(t);
  if ((bigger || smaller) && aboutText && _findColor(t) == null) {
    final scale = (current.fontScale ?? 1.0) + (bigger ? 0.15 : -0.15);
    return QuickStyle(fontScale: double.parse(scale.clamp(0.7, 1.6).toStringAsFixed(2)));
  }

  // Font family.
  const fontWords = {
    'serif': 'classic',
    'classic': 'classic',
    'times': 'classic',
    'georgia': 'classic',
    'modern': 'modern',
    'sans': 'modern',
    'rounded': 'rounded',
    'friendly': 'rounded',
    'typewriter': 'code',
    'monospace': 'code',
    'code font': 'code',
    'handwriting': 'handwriting',
    'handwritten': 'handwriting',
    'comic': 'handwriting',
  };
  if (RegExp(r'\b(font|typeface|writing style|lettering)\b').hasMatch(t) ||
      fontWords.keys.any((w) => t.contains(w) && !t.contains('colo'))) {
    for (final e in fontWords.entries) {
      if (t.contains(e.key)) return QuickStyle(fontFamily: e.value);
    }
  }

  // Colours.
  final color = _findColor(t);
  if (color == null) return null;
  final colorWord = RegExp(r'\b(colou?r|make|change|set|turn|use|paint|want)\b').hasMatch(t) ||
      t.split(' ').length <= 4;
  if (!colorWord) return null;

  // Bars first: "make the navbar background blue" is about the bar.
  if (RegExp(r'\b(nav ?bar|navigation|top ?bar|header|menu ?bar|app ?bar|nav)\b').hasMatch(t)) {
    return QuickStyle(barColor: color);
  }
  // Colour for some other part of the page (a card, the logo, one section):
  // that needs the page's own structure, so it is the coder model's job.
  if (RegExp(r'\b(logo|card|cards|section|footer|image|picture|photo|box|border|icon|table|form|sidebar)s?\b')
      .hasMatch(t)) {
    return null;
  }
  if (RegExp(r'\b(background|backdrop|bg|page colou?r|behind)\b').hasMatch(t)) {
    return QuickStyle(backgroundColor: color);
  }
  if (RegExp(r'\b(headings?|titles?|headlines?|headers? text)\b').hasMatch(t)) {
    return QuickStyle(headingColor: color);
  }
  if (RegExp(r'\b(buttons?|links?|accent|theme|main colou?r|primary)\b').hasMatch(t)) {
    return QuickStyle(accentColor: color);
  }
  if (RegExp(r'\b(text|font|words|writing|letters|paragraphs?)\b').hasMatch(t)) {
    return QuickStyle(textColor: color);
  }
  // "make it green" — the theme colour is what students mean most often.
  // Only for short requests; anything longer is probably about something
  // specific and goes to the coder model.
  if (t.split(' ').length <= 5) return QuickStyle(accentColor: color);
  return null;
}

/// Black or white — whichever reads better on [hex] (WCAG luminance).
String readableTextOn(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  final v = int.tryParse(h, radix: 16);
  if (v == null || h.length != 6) return '#ffffff';
  double channel(int c) {
    final s = c / 255;
    return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4).toDouble();
  }
  final l = 0.2126 * channel((v >> 16) & 0xff) +
      0.7152 * channel((v >> 8) & 0xff) +
      0.0722 * channel(v & 0xff);
  return l > 0.4 ? '#111827' : '#ffffff';
}

final _blockRe = RegExp(
  r'<style id="otic-style">[\s\S]*?</style>\s*',
  caseSensitive: false,
);
final _jsonRe = RegExp(r'/\* otic-style (\{[\s\S]*?\}) \*/');

/// The style already applied to [html] (empty when none).
QuickStyle readQuickStyle(String html) {
  final block = _blockRe.firstMatch(html)?.group(0);
  if (block == null) return const QuickStyle();
  final json = _jsonRe.firstMatch(block)?.group(1);
  if (json == null) return const QuickStyle();
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, Object?>) return QuickStyle.fromJson(decoded);
  } catch (_) {}
  return const QuickStyle();
}

/// Writes [style] into [html] (replacing any earlier block). Placed last in
/// `<head>` so it wins over the template's own CSS.
String applyQuickStyle(String html, QuickStyle style) {
  final without = html.replaceAll(_blockRe, '');
  if (style.isEmpty) return without;
  final css = StringBuffer()
    ..writeln('<style id="otic-style">')
    ..writeln('/* otic-style ${jsonEncode(style.toJson())} */');
  if (style.fontScale != null && style.fontScale != 1.0) {
    css.writeln('html{font-size:${(style.fontScale! * 100).round()}% !important}');
  }
  final font = style.fontFamily == null ? null : kQuickFonts[style.fontFamily]?.stack;
  if (font != null) {
    css.writeln('body,button,input,textarea,select,h1,h2,h3,h4,h5,h6{font-family:$font !important}');
  }
  if (style.backgroundColor != null) {
    css.writeln('html,body{background:${style.backgroundColor} !important}');
  }
  if (style.textColor != null) {
    css.writeln('body,p,li,span,label,td,th,small,blockquote,figcaption,dd,dt'
        '{color:${style.textColor} !important}');
  }
  if (style.headingColor != null) {
    css.writeln('h1,h2,h3,h4,h5,h6{color:${style.headingColor} !important}');
  }
  if (style.barColor != null) {
    final b = style.barColor!;
    final on = readableTextOn(b);
    css
      ..writeln('header,nav,.navbar,.topbar,.top-bar,.app-bar,.appbar'
          '{background:$b !important;color:$on !important}')
      ..writeln('header a,nav a,.navbar a,.topbar a{color:$on !important}');
  }
  if (style.accentColor != null) {
    final a = style.accentColor!;
    final on = readableTextOn(a);
    css
      ..writeln(':root{--primary:$a;--accent:$a;--brand:$a}')
      ..writeln('a{color:$a !important}')
      ..writeln('button,.btn,[class*="btn"],input[type=submit],input[type=button]'
          '{background:$a !important;border-color:$a !important;color:$on !important}');
  }
  css.write('</style>\n');

  final i = without.toLowerCase().lastIndexOf('</head>');
  if (i < 0) return '$css$without';
  return '${without.substring(0, i)}$css${without.substring(i)}';
}
