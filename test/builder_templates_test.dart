import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guard for the hand-written builder templates.
///
/// These files are the only thing standing between a student and a blank
/// preview now that both builders assemble from them deterministically, so a
/// malformed one is a shipped bug rather than a fallback.
void main() {
  const siteTemplates = [
    'bakery', 'hotel', 'fitness', 'salon', 'church', 'realtor',
    'techstartup', 'ngo', 'portfolio', 'school',
    'agritech', 'saasai', 'taskflow', 'edudash', 'smartedu',
  ];
  const appTemplates = [
    'generic', 'farm', 'shop', 'learn', 'pos',
    'social', 'eduplatform', 'orders', 'products',
  ];

  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  void checkDocument(String html, String label) {
    expect(
      html.trimLeft().toLowerCase().startsWith('<!doctype html>'),
      isTrue,
      reason: '$label must start with a doctype',
    );
    expect(html.toLowerCase(), contains('</html>'), reason: '$label unclosed');

    for (final tag in ['style', 'html', 'head', 'body']) {
      // The optional-attribute group must start with whitespace, otherwise
      // `<head...>` also matches `<header>`.
      final open = RegExp('<$tag(?:\\s[^>]*)?>', caseSensitive: false)
          .allMatches(html)
          .length;
      final close =
          RegExp('</$tag>', caseSensitive: false).allMatches(html).length;
      expect(
        open,
        close,
        reason: '$label has $open <$tag> but $close </$tag>',
      );
    }

    // A template with no tokens would render identically for every student.
    expect(
      RegExp(r'\{\{[a-zA-Z0-9_]+\}\}').hasMatch(html),
      isTrue,
      reason: '$label substitutes nothing',
    );
  }

  test('every site template is a complete, token-bearing document', () {
    for (final id in siteTemplates) {
      checkDocument(read('assets/templates/$id.html'), 'site/$id');
    }
  });

  test('every app template is a complete, token-bearing document', () {
    for (final id in appTemplates) {
      checkDocument(read('assets/templates/apps/$id.html'), 'app/$id');
    }
  });

  test('app templates carry the tokens every build always supplies', () {
    // These are filled for any app type, so a template may rely on them.
    for (final id in appTemplates) {
      final html = read('assets/templates/apps/$id.html');
      expect(html, contains('{{app_name}}'), reason: 'app/$id names nothing');
      expect(html, contains('{{primary}}'), reason: 'app/$id ignores the theme');
      expect(
        html,
        contains('{{features}}'),
        reason: 'app/$id never shows the chosen features',
      );
    }
  });

  test('no template hard-codes a raw CSS placeholder typo', () {
    for (final path in [
      for (final id in siteTemplates) 'assets/templates/$id.html',
      for (final id in appTemplates) 'assets/templates/apps/$id.html',
    ]) {
      final css = RegExp(
        r'<style[^>]*>([\s\S]*?)</style>',
        caseSensitive: false,
      ).firstMatch(read(path))?.group(1);
      expect(css, isNotNull, reason: '$path has no stylesheet');
      // A custom property holding a colour followed by a bare word is the
      // shape of a typo like "--pop:#f5e busy" — never a deliberate value.
      expect(
        RegExp(r'--[\w-]+\s*:\s*#[0-9a-fA-F]{3,8}\s+[a-zA-Z]+\s*;')
            .hasMatch(css!),
        isFalse,
        reason: '$path has a malformed custom property',
      );
    }
  });
}
