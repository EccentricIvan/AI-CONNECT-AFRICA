/// Makes student / model HTML safe to hand to a WebView — repair only.
///
/// This layer never invents content. Whatever the editor shows on the left is
/// what the preview paints on the right: if the page has no JavaScript, it
/// renders without JavaScript; if a button has no handler, it stays dead.
/// The only things done here are closing tags the on-device coder truncated
/// mid-generation and wrapping a bare fragment in a minimal document so the
/// browser has a charset, a viewport, and readable defaults.
String ensureRenderableHtmlDocument(String raw) {
  final stripped = _stripFences(raw).trim();
  if (stripped.isEmpty) return kEmptyPreviewDocument;

  final repaired = _repairTruncatedDocument(stripped);
  if (_hasDocumentStructure(repaired)) return repaired;
  return _wrapFragment(repaired);
}

String _stripFences(String raw) {
  var s = raw.trim();
  final fenced = RegExp(
    r'```(?:html|HTML|htm)?\s*([\s\S]*?)```',
    multiLine: true,
  ).firstMatch(s);
  if (fenced != null) s = (fenced.group(1) ?? '').trim();
  s = s.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  return s.trim();
}

/// True when [html] already is a document the browser can parse on its own.
bool _hasDocumentStructure(String html) =>
    RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(html) &&
    RegExp(r'<body[\s>]', caseSensitive: false).hasMatch(html);

/// Closes what the coder left open. A truncated `<script>` or `<style>` swallows
/// the rest of the document in the parser, so those are closed first.
String _repairTruncatedDocument(String html) {
  var out = html;

  final styleOpen =
      RegExp(r'<style\b', caseSensitive: false).allMatches(out).length;
  final styleClose =
      RegExp(r'</style\s*>', caseSensitive: false).allMatches(out).length;
  if (styleOpen > styleClose) {
    out = '$out\n</style>';
  }

  final scriptOpen =
      RegExp(r'<script\b', caseSensitive: false).allMatches(out).length;
  final scriptClose =
      RegExp(r'</script\s*>', caseSensitive: false).allMatches(out).length;
  if (scriptOpen > scriptClose) {
    // Soft-close truncated JS so the browser can still parse the DOM below it.
    out = '$out\n}catch(e){}\n</script>';
  }

  if (!RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(out) &&
      RegExp(r'<html', caseSensitive: false).hasMatch(out)) {
    out = '<!DOCTYPE html>\n$out';
  }
  if (RegExp(r'<body[\s>]', caseSensitive: false).hasMatch(out) &&
      !RegExp(r'</body\s*>', caseSensitive: false).hasMatch(out)) {
    out = '$out\n</body>';
  }
  if (RegExp(r'<html', caseSensitive: false).hasMatch(out) &&
      !RegExp(r'</html\s*>', caseSensitive: false).hasMatch(out)) {
    out = '$out\n</html>';
  }
  return out;
}

/// Wraps body-only markup in a document. The stylesheet is typography and
/// spacing only — no components, no layout opinions, nothing that could be
/// mistaken for the student's own design.
String _wrapFragment(String fragment) => '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${_titleOf(fragment) ?? 'Preview'}</title>
<style>
*{box-sizing:border-box}
body{margin:0;padding:24px;background:#fff;color:#111827;line-height:1.55;
  font-family:system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif}
img{max-width:100%}
</style>
</head>
<body>
$fragment
</body>
</html>
''';

String? _titleOf(String html) {
  final m = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(html);
  final title = m?.group(1)?.trim();
  return (title == null || title.isEmpty) ? null : escapeHtml(title);
}

/// Escapes text for safe interpolation into HTML markup — a stray `<` or `&`
/// in student-typed input (a name, a phone number) must render as text, not
/// be parsed as a tag.
String escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Shown when there is genuinely nothing to render yet. Deliberately a status
/// message rather than a sample page — a fake site here is what made the
/// preview untrustworthy in the first place.
const kEmptyPreviewDocument = '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Preview</title>
<style>
body{margin:0;height:100vh;display:grid;place-items:center;background:#f8fafc;
  color:#94a3b8;font-family:system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif}
p{margin:0;font-size:14px}
</style>
</head>
<body><p>Nothing to preview yet — write some HTML on the left.</p></body>
</html>
''';
