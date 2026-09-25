import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/projects/project_store.dart';
import '../../shared/coding/html_images.dart' show PickedImage;

/// The page a project opens on: `frontend/index.html`, else `index.html`.
Future<File?> projectEntryPage(ProjectFolder folder) async {
  for (final rel in const ['frontend/index.html', 'index.html']) {
    final f = File(p.joinAll([folder.path, ...rel.split('/')]));
    if (await f.exists()) return f;
  }
  return null;
}

/// One self-contained HTML string for the in-app preview: linked
/// stylesheets and scripts are inlined and local pictures become data URIs,
/// because the preview renders a string, not a folder on a web server.
Future<String?> buildProjectPreviewHtml(ProjectFolder folder) async {
  final entry = await projectEntryPage(folder);
  if (entry == null) return null;
  final dir = entry.parent.path;
  var html = await entry.readAsString();

  Future<String?> read(String rel) async {
    if (rel.startsWith('http') || rel.startsWith('//') || rel.contains('..')) return null;
    final f = File(p.joinAll([dir, ...rel.split('?').first.split('/')]));
    return await f.exists() ? f.readAsString() : null;
  }

  Future<String?> dataUri(String rel) async {
    if (rel.startsWith('data:') || rel.startsWith('http') || rel.contains('..')) return null;
    final mime = PickedImage.mimeFor(rel);
    if (mime == null) return null;
    final f = File(p.joinAll([dir, ...rel.split('?').first.split('/')]));
    if (!await f.exists()) return null;
    return 'data:$mime;base64,${base64Encode(await f.readAsBytes())}';
  }

  Future<String> replaceAsync(
      String input, RegExp re, Future<String?> Function(Match m) fn) async {
    final out = StringBuffer();
    var last = 0;
    for (final m in re.allMatches(input)) {
      out.write(input.substring(last, m.start));
      out.write(await fn(m) ?? m.group(0));
      last = m.end;
    }
    out.write(input.substring(last));
    return out.toString();
  }

  // <link rel="stylesheet" href="css/x.css"> → <style>…</style>
  html = await replaceAsync(
    html,
    RegExp(r'''<link\b[^>]*rel=["']stylesheet["'][^>]*href=["']([^"']+)["'][^>]*>''',
        caseSensitive: false),
    (m) async {
      var css = await read(m.group(1)!);
      if (css == null) return null;
      // url(../images/x.png) inside the stylesheet, relative to the css file.
      final cssDir = p.posix.dirname(m.group(1)!);
      css = await replaceAsync(
        css,
        RegExp(r'''url\(\s*["']?([^"')]+)["']?\s*\)'''),
        (u) async {
          final target = p.posix.normalize(p.posix.join(cssDir, u.group(1)!));
          final uri = await dataUri(target);
          return uri == null ? null : 'url("$uri")';
        },
      );
      return '<style>\n$css\n</style>';
    },
  );

  // <script src="js/x.js"></script> → inline (skip the service worker).
  html = await replaceAsync(
    html,
    RegExp(r'''<script\b([^>]*)\bsrc=["']([^"']+)["']([^>]*)>\s*</script>''',
        caseSensitive: false),
    (m) async {
      final js = await read(m.group(2)!);
      if (js == null) return null;
      return '<script>\n${js.replaceAll('</script', r'<\/script')}\n</script>';
    },
  );

  // <img src="images/x.png"> → data URI
  html = await replaceAsync(
    html,
    RegExp(r'''(<img\b[^>]*\bsrc=)(["'])([^"']+)\2''', caseSensitive: false),
    (m) async {
      final uri = await dataUri(m.group(3)!);
      return uri == null ? null : '${m.group(1)}${m.group(2)}$uri${m.group(2)}';
    },
  );
  return html;
}
