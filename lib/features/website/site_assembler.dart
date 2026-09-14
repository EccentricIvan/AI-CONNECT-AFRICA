import 'package:flutter/services.dart';

import 'site_blocks.dart';

/// Assembles a finished page from the premium block library.
///
/// Layout and CSS are deterministic: the coder model never emits structure, so
/// a build cannot produce a broken page. Model output arrives as [modelCopy]
/// and is layered over the vertical defaults, which remain the fallback for
/// any token the model omits or truncates.
class SiteAssembler {
  SiteAssembler({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final _cache = <String, String>{};

  static const _dir = 'assets/templates/blocks';

  Future<String> _load(String name) async {
    final hit = _cache[name];
    if (hit != null) return hit;
    final text = await _bundle.loadString('$_dir/$name');
    _cache[name] = text;
    return text;
  }

  /// Builds the full HTML document.
  ///
  /// [selected] is filtered to known blocks and always re-sorted into
  /// [kSectionOrder], so selection order cannot scramble the page.
  Future<String> assemble({
    required SiteVertical vertical,
    required Set<String> selected,
    Map<String, String> answers = const {},
    Map<String, String> modelCopy = const {},
  }) async {
    final blocks = <String>[
      for (final id in kSectionOrder)
        if (kCoreBlocks.contains(id) || selected.contains(id)) id,
    ];

    // Blank values are dropped *before* merging. Stripping them afterwards
    // would delete the default sitting underneath, so an empty or truncated
    // model field would blank the section instead of falling back to it.
    final tokens = <String, String>{
      ...kBaseCopy,
      ...vertical.copy,
      ..._nonEmpty(modelCopy),
      // Student-entered answers win over everything: they are facts, not copy.
      ..._nonEmpty(answers),
    };

    final siteName = tokens['site_name']?.trim();
    if (siteName == null || siteName.isEmpty) {
      tokens['site_name'] = vertical.name;
    }
    tokens['initial'] = _initial(tokens['site_name']!);
    tokens['year'] = DateTime.now().year.toString();
    tokens['brand'] = vertical.brand;
    tokens['brand2'] = vertical.brand2;
    tokens['nav_links'] = _navLinks(blocks);
    tokens.putIfAbsent('headline', () => tokens['site_name']!);
    tokens.putIfAbsent(
      'subhead',
      () => tokens['about_text'] ?? kBaseCopy['about_text']!,
    );
    _seedInitials(tokens);

    final css = _fill(await _load('base.css'), tokens);
    final body = StringBuffer();
    for (final id in blocks) {
      body.writeln(_fill(await _load('$id.html'), tokens));
    }

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(tokens['site_name']!)}</title>
<style>
$css
</style>
</head>
<body>
$body</body>
</html>
''';
  }

  static Map<String, String> _nonEmpty(Map<String, String> src) => {
        for (final e in src.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      };

  /// Anchor list for the sticky nav — only links to sections actually present.
  String _navLinks(List<String> blocks) {
    final out = StringBuffer();
    for (final id in blocks) {
      final label = kNavLabels[id];
      if (label == null) continue;
      out.write('<a href="#$id">$label</a>');
    }
    return out.toString();
  }

  /// Avatar/monogram letters are derived, never asked for.
  void _seedInitials(Map<String, String> t) {
    for (final p in ['quote1', 'quote2', 'quote3']) {
      t['${p}_initial'] = _initial(t['${p}_name'] ?? '?');
    }
    for (final p in ['person1', 'person2', 'person3', 'person4']) {
      t['${p}_initial'] = _initial(t['${p}_name'] ?? '?');
    }
  }

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }

  /// Tokens whose values are markup this class generated itself, so escaping
  /// them would render the tags as visible text.
  static const _rawTokens = {'nav_links'};

  /// Replaces `{{token}}`. Unknown tokens are stripped rather than left
  /// visible, so a missing key never renders as literal braces on the page.
  /// Everything a student or the model supplied is escaped — a stray `<` in a
  /// business name must not be able to inject markup into the page.
  static String _fill(String src, Map<String, String> tokens) {
    return src.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
      final key = m.group(1)!;
      final value = tokens[key] ?? '';
      return _rawTokens.contains(key) ? value : _escape(value);
    });
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
