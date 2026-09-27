import 'html_images.dart';
import 'interactive_html.dart' show escapeHtml;

/// What a picture + instruction did to a page.
class ImageEditResult {
  const ImageEditResult({
    required this.html,
    required this.summary,
    this.wantsColours = false,
    this.modelInstruction,
  });

  final String html;

  /// Plain-English description of what happened, for the snackbar.
  final String summary;

  /// The learner asked for the page to take the picture's colours; the
  /// caller reads them from the pixels (see `paletteStyleFromImageBytes`).
  final bool wantsColours;

  /// Leftover styling the rules below don't cover ("tilt it slightly"),
  /// phrased for the coder model with the placed picture's selector.
  final String? modelInstruction;
}

/// Carries out "do this with the picture I attached" — "make it the logo",
/// "use it as the background", "put it in the about section", "replace the
/// second picture", "make it round", "use its colours".
///
/// The coder model reads text only and can't see the picture, so the
/// instruction decides where the picture goes, and the placement is done
/// here, exactly. Only styling this can't express is left for the model.
ImageEditResult applyImageInstruction(
  String html,
  String instruction,
  List<PickedImage> images,
) {
  if (images.isEmpty) return ImageEditResult(html: html, summary: '');
  final lower = instruction.toLowerCase();
  final wantsColours =
      _coloursRe.hasMatch(lower) && !_colourNamedRe.hasMatch(lower);
  final colourOnly = wantsColours && !_placementRe.hasMatch(lower);

  var out = html;
  String? selector;
  final done = <String>[];
  var rest = images;

  if (colourOnly) {
    rest = const [];
  } else if (_logoRe.hasMatch(lower) && _hasBar(out)) {
    out = setLogo(out, images.first);
    selector = 'header img, nav img';
    done.add('set as the logo');
    rest = images.sublist(1);
  } else if (_logoRe.hasMatch(lower)) {
    // No top bar to hold a logo: put it first on the page instead.
    final body = RegExp(r'<body\b[^>]*>', caseSensitive: false).firstMatch(out);
    final cls = _nextImgClass(out);
    final logo =
        '<img src="${images.first.dataUri}" alt="${escapeHtml(images.first.altText)}" '
        'class="otic-img $cls" style="height:64px;width:auto;display:block;margin:16px auto">';
    final at = body?.end ?? 0;
    out = '${out.substring(0, at)}$logo${out.substring(at)}';
    selector = '.$cls';
    done.add('set as the logo at the top of the page');
    rest = images.sublist(1);
  } else if (_backgroundRe.hasMatch(lower)) {
    final wholePage = _wholePageRe.hasMatch(lower);
    final placed = _setBackground(out, images.first, wholePage: wholePage);
    out = placed.html;
    done.add(placed.where);
    rest = images.sublist(1);
  } else if (_replaceRe.hasMatch(lower) && listPageImages(out).isNotEmpty) {
    final count = listPageImages(out).length;
    final index = _ordinal(lower, count).clamp(0, count - 1);
    out = replacePageImage(out, index, images.first);
    final cls = _nextImgClass(out);
    out = _tagImgAt(out, index, cls);
    selector = '.$cls';
    done.add('replaced picture ${index + 1}');
    rest = images.sublist(1);
  } else if (!_galleryRe.hasMatch(lower)) {
    final spot = _findSpot(out, lower);
    if (spot != null) {
      final cls = _nextImgClass(out);
      final tag = _imgTag(images.first, cls);
      out = '${out.substring(0, spot.at)}$tag${out.substring(spot.at)}';
      selector = '.$cls';
      done.add(spot.where);
      rest = images.sublist(1);
    }
  }

  if (rest.isNotEmpty) {
    out = addToGallery(out, rest);
    selector ??= '.otic-gallery img';
    done.add(
      rest.length == 1
          ? 'added to the gallery'
          : 'added ${rest.length} pictures to the gallery',
    );
  }

  String? modelInstruction;
  if (selector != null) {
    final style = _styleRules(lower, selector);
    if (style.css.isNotEmpty) {
      out = _appendStyle(out, style.css);
      done.add(style.what.join(', '));
    }
    if (_hasUnhandledStyling(lower)) {
      modelInstruction =
          'Style only the picture(s) matching `$selector`: $instruction';
    }
  }
  if (wantsColours) done.add('page colours taken from the picture');

  final summary = done.isEmpty
      ? 'Picture added.'
      : '${_capitalise(done.join('; '))}.';
  return ImageEditResult(
    html: out,
    summary: summary,
    wantsColours: wantsColours,
    modelInstruction: modelInstruction,
  );
}

// ── What the instruction asks for ─────────────────────────────────────────

final _coloursRe = RegExp(
  r'\b(colou?rs?|palette|theme|colou?r scheme|match)\b',
);
// "make the background blue" names a colour instead of taking the picture's.
final _colourNamedRe = RegExp(
  r'\b(red|blue|green|yellow|orange|purple|pink|black|white|gr[ae]y|brown|gold)\b',
);
final _logoRe = RegExp(r'\b(logo|brand|icon)\b');
final _backgroundRe = RegExp(
  r'\b(background|backdrop|wallpaper|behind|hero|banner|cover)\b(?!\s+colou?r)',
);
final _wholePageRe = RegExp(
  r'\b(whole|entire|full|all|page|website|site|app)\b',
);
final _replaceRe = RegExp(r'\b(replace|swap|instead|change)\b');
final _galleryRe = RegExp(r'\b(gallery|album|slideshow|photos section)\b');
final _placementRe = RegExp(
  r'\b(logo|brand|icon|background|backdrop|wallpaper|behind|hero|banner|cover|'
  r'replace|swap|instead|gallery|album|put|place|add|insert|show|top|bottom|'
  r'section|next to|under|above|below|beside)\b',
);

int _ordinal(String lower, int count) {
  if (RegExp(r'\blast\b').hasMatch(lower)) return count - 1;
  const words = {
    'first': 0,
    '1st': 0,
    'second': 1,
    '2nd': 1,
    'third': 2,
    '3rd': 2,
    'fourth': 3,
    '4th': 3,
    'fifth': 4,
    '5th': 4,
  };
  for (final e in words.entries) {
    if (RegExp('\\b${e.key}\\b').hasMatch(lower)) return e.value;
  }
  final n = RegExp(
    r'\b(?:picture|image|photo|pic)\s*(\d{1,2})\b',
  ).firstMatch(lower);
  if (n != null) return int.parse(n.group(1)!) - 1;
  return 0;
}

// ── Placement ─────────────────────────────────────────────────────────────

bool _hasBar(String html) {
  final lower = html.toLowerCase();
  return lower.contains('<header') || lower.contains('<nav');
}

final _openTagRe = RegExp(
  r'<(section|div|header|footer|article|aside|main|nav)\b[^>]*>',
  caseSensitive: false,
);
final _headingRe = RegExp(
  r'<(h[1-4])\b[^>]*>([\s\S]*?)</\1\s*>',
  caseSensitive: false,
);

const _stopWords = {
  'put',
  'this',
  'that',
  'the',
  'image',
  'picture',
  'photo',
  'pic',
  'section',
  'part',
  'page',
  'add',
  'into',
  'next',
  'under',
  'above',
  'below',
  'near',
  'beside',
  'with',
  'and',
  'make',
  'use',
  'place',
  'insert',
  'show',
  'there',
  'here',
  'area',
  'app',
  'website',
  'site',
  'please',
  'its',
  'for',
  'from',
  'inside',
  'onto',
  'top',
  'bottom',
  'before',
  'after',
  'right',
  'left',
  'center',
  'centre',
  'middle',
  'round',
  'small',
  'big',
  'bigger',
  'smaller',
  'large',
  'larger',
  'want',
  'can',
  'you',
  'our',
  'your',
  'them',
  'these',
  'screen',
  'app\'s',
  'website\'s',
  'one',
};

({int at, String where})? _findSpot(String html, String lower) {
  final words = RegExp(r'[a-z]{3,}')
      .allMatches(lower)
      .map((m) => m.group(0)!)
      .where((w) => !_stopWords.contains(w))
      .toList();
  final before = RegExp(r'\b(above|before|over)\b').hasMatch(lower);

  for (final word in words) {
    for (final h in _headingRe.allMatches(html)) {
      final text = h
          .group(2)!
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .toLowerCase();
      if (!RegExp('\\b${RegExp.escape(word)}').hasMatch(text)) continue;
      final label = h.group(2)!.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
      return before
          ? (at: h.start, where: 'put above “$label”')
          : (at: h.end, where: 'put under “$label”');
    }
  }
  for (final word in words) {
    for (final t in _openTagRe.allMatches(html)) {
      final tag = t.group(0)!.toLowerCase();
      final attrs = RegExp(
        r'''(?:id|class)\s*=\s*["']([^"']*)["']''',
      ).allMatches(tag).map((m) => m.group(1)!).join(' ');
      if (!attrs.contains(word)) continue;
      return (at: t.end, where: 'put in the $word section');
    }
  }

  final lowerHtml = html.toLowerCase();
  if (RegExp(r'\b(top|beginning|start)\b').hasMatch(lower)) {
    final headerEnd = lowerHtml.indexOf('</header>');
    if (headerEnd >= 0) {
      return (at: headerEnd + '</header>'.length, where: 'put at the top');
    }
    final body = RegExp(
      r'<body\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (body != null) return (at: body.end, where: 'put at the top');
  }
  if (RegExp(r'\b(bottom|end)\b').hasMatch(lower)) {
    var at = lowerHtml.lastIndexOf('<footer');
    if (at < 0) at = lowerHtml.lastIndexOf('</body>');
    if (at >= 0) return (at: at, where: 'put at the bottom');
  }
  return null;
}

({String html, String where}) _setBackground(
  String html,
  PickedImage image, {
  required bool wholePage,
}) {
  Match? target;
  var where = 'set as the page background';
  if (!wholePage) {
    target = _openTagRe
        .allMatches(html)
        .cast<Match?>()
        .firstWhere(
          (m) => RegExp(
            r'hero|banner|cover|masthead|jumbotron|intro',
            caseSensitive: false,
          ).hasMatch(m!.group(0)!),
          orElse: () => null,
        );
    target ??= RegExp(
      r'<header\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (target != null) where = 'set as the banner background';
  }
  target ??= RegExp(r'<body\b[^>]*>', caseSensitive: false).firstMatch(html);
  if (target == null) return (html: html, where: where);

  final isBody = target.group(0)!.toLowerCase().startsWith('<body');
  // A see-through wash keeps the page's text readable on any photo.
  final style = isBody
      ? "background-image:linear-gradient(rgba(255,255,255,.82),rgba(255,255,255,.82)),"
            "url('${image.dataUri}') !important;background-size:cover !important;"
            'background-position:center !important;background-attachment:fixed !important'
      : "background-image:linear-gradient(rgba(0,0,0,.45),rgba(0,0,0,.45)),"
            "url('${image.dataUri}') !important;background-size:cover !important;"
            'background-position:center !important;color:#fff !important';
  final tag = _addInlineStyle(target.group(0)!, style);
  return (
    html: '${html.substring(0, target.start)}$tag${html.substring(target.end)}',
    where: where,
  );
}

String _addInlineStyle(String openTag, String style) {
  final existing = RegExp(
    r'''\sstyle\s*=\s*(["'])(.*?)\1''',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(openTag);
  if (existing != null) {
    final merged =
        '${existing.group(2)!.trim().replaceAll(RegExp(r';?$'), ';')}$style';
    return openTag.replaceRange(
      existing.start,
      existing.end,
      ' style="$merged"',
    );
  }
  final close = openTag.endsWith('/>')
      ? openTag.length - 2
      : openTag.length - 1;
  return '${openTag.substring(0, close)} style="$style"${openTag.substring(close)}';
}

String _nextImgClass(String html) {
  var n = 1;
  while (html.contains('otic-img-$n')) {
    n++;
  }
  return 'otic-img-$n';
}

String _imgTag(PickedImage image, String cls) =>
    '<img src="${image.dataUri}" alt="${escapeHtml(image.altText)}" class="otic-img $cls" '
    'style="max-width:100%;height:auto;display:block;margin:16px auto;border-radius:12px">';

final _imgRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);

String _tagImgAt(String html, int index, String cls) {
  var i = 0;
  return html.replaceAllMapped(_imgRe, (m) {
    if (i++ != index) return m.group(0)!;
    final tag = m.group(0)!;
    final classAttr = RegExp(
      r'''\sclass\s*=\s*(["'])(.*?)\1''',
      caseSensitive: false,
    ).firstMatch(tag);
    if (classAttr != null) {
      return tag.replaceRange(
        classAttr.start,
        classAttr.end,
        ' class="${classAttr.group(2)} $cls"',
      );
    }
    return tag.replaceFirst(
      RegExp(r'<img', caseSensitive: false),
      '<img class="$cls"',
    );
  });
}

// ── Styling the placed picture ────────────────────────────────────────────

({String css, List<String> what}) _styleRules(String lower, String selector) {
  final rules = <String>[];
  final what = <String>[];
  void rule(String css, String label) {
    rules.add(css);
    what.add(label);
  }

  if (RegExp(r'\brounded\b|\bcorners?\b').hasMatch(lower)) {
    rule('border-radius:18px !important', 'rounded corners');
  } else if (RegExp(r'\b(round|circle|circular)\b').hasMatch(lower)) {
    rule(
      'border-radius:50% !important;aspect-ratio:1/1;object-fit:cover;'
          'width:min(220px,60vw) !important',
      'made round',
    );
  }
  if (RegExp(r'\b(small|smaller|tiny|little)\b').hasMatch(lower)) {
    rule('max-width:240px !important', 'made smaller');
  } else if (RegExp(
    r'\b(big|bigger|large|larger|full width|wide|wider)\b',
  ).hasMatch(lower)) {
    rule('width:100% !important;max-width:100% !important', 'made bigger');
  }
  if (RegExp(r'\bleft\b').hasMatch(lower)) {
    rule(
      'float:left;margin:0 16px 12px 0 !important;max-width:45% !important',
      'moved left',
    );
  } else if (RegExp(r'\bright\b').hasMatch(lower)) {
    rule(
      'float:right;margin:0 0 12px 16px !important;max-width:45% !important',
      'moved right',
    );
  } else if (RegExp(r'\b(center|centre|middle)\b').hasMatch(lower)) {
    rule(
      'display:block !important;margin:16px auto !important;float:none !important',
      'centred',
    );
  }
  if (RegExp(r'\bshadow\b').hasMatch(lower)) {
    rule('box-shadow:0 12px 30px rgba(0,0,0,.2) !important', 'shadow added');
  }
  if (RegExp(r'\b(border|frame)\b').hasMatch(lower)) {
    rule('border:4px solid var(--primary,#2563eb) !important', 'framed');
  }
  if (RegExp(
    r'black and white|\b(gr[ae]y|grayscale|greyscale)\b',
  ).hasMatch(lower)) {
    rule('filter:grayscale(1) !important', 'made black and white');
  }
  if (rules.isEmpty) return (css: '', what: const []);
  final css = rules.map((r) => '$selector{$r}').join('\n');
  return (css: css, what: what);
}

// Styling words handled above don't need the model; these do.
final _modelStylingRe = RegExp(
  r'\b(tilt|rotate|angle|blur|fade|faded|transparent|opacity|glow|darker|'
  r'brighter|sepia|flip|mirror|zoom|animate|animation|hover|outline|overlay|'
  r'caption|spacing|padding|margin)\b',
);

bool _hasUnhandledStyling(String lower) => _modelStylingRe.hasMatch(lower);

String _appendStyle(String html, String css) {
  final block = '<style>\n/* picture style */\n$css\n</style>';
  final i = html.toLowerCase().lastIndexOf('</head>');
  if (i < 0) return '$block\n$html';
  return '${html.substring(0, i)}$block\n${html.substring(i)}';
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
