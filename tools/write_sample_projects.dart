// Writes sample projects into a folder, so tools/verify_scaffolds.ps1 can
// install and test the generated backends and syntax-check the frontends:
//
// * one app per app type (backend coverage), and
// * one project per real template in assets/templates (frontend coverage —
//   the merged scripts of every shipped template must still parse).
//
//   dart run tools/write_sample_projects.dart <out-dir>
import 'dart:io';

import 'package:ai_connect_africa/features/projects/scaffold/project_scaffold.dart';

const _appTypes = [
  'todo', 'notes', 'budget', 'quiz', 'habits', 'market', 'farm', 'shop',
  'learn', 'pos', 'social', 'eduplatform', 'orders', 'products', 'calculator',
  'something-new',
];

const _sampleHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Sample</title>
<style>:root{--primary:#2563EB} body{font-family:system-ui}</style>
</head>
<body>
<h1>Sample</h1>
<form><input name="name"><input type="email" name="email"><textarea name="message"></textarea><button>Send</button></form>
<script>document.querySelector('h1').addEventListener('click', function(){});</script>
</body>
</html>
''';

void _write(Directory root, Map<String, String> files) {
  for (final e in files.entries) {
    final f = File('${root.path}/${e.key}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(e.value);
  }
}

String _fillTokens(String html) =>
    html.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) => m.group(1) == 'primary' ? '#2563EB' : 'Sample');

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tools/write_sample_projects.dart <out-dir>');
    exit(64);
  }
  final out = Directory(args.first)..createSync(recursive: true);
  var n = 0;
  _write(
    Directory('${out.path}/website'),
    buildWebsiteProject(
      title: 'Sample Bakery',
      html: _sampleHtml,
      templateName: 'Bakery',
      siteContent: {'tagline': 'Fresh bread daily'},
    ),
  );
  n++;
  for (final id in _appTypes) {
    _write(
      Directory('${out.path}/app-$id'),
      buildAppProject(title: 'Sample $id', html: _sampleHtml, appTypeId: id),
    );
    n++;
  }

  // Real shipped templates: frontends only (the backends are covered above).
  final frontends = Directory('${out.path}/_frontends')..createSync(recursive: true);
  for (final f in Directory('assets/templates').listSync().whereType<File>()) {
    if (!f.path.endsWith('.html')) continue;
    final name = f.uri.pathSegments.last.replaceAll('.html', '');
    _write(
      Directory('${frontends.path}/site-$name'),
      buildWebsiteProject(title: name, html: _fillTokens(f.readAsStringSync())),
    );
    n++;
  }
  for (final f in Directory('assets/templates/apps').listSync().whereType<File>()) {
    if (!f.path.endsWith('.html')) continue;
    final name = f.uri.pathSegments.last.replaceAll('.html', '');
    _write(
      Directory('${frontends.path}/app-$name'),
      buildAppProject(title: name, html: _fillTokens(f.readAsStringSync()), appTypeId: name),
    );
    n++;
  }
  stdout.writeln('Wrote $n projects to ${out.path}');
}
