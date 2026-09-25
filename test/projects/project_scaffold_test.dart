import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/features/projects/scaffold/frontend_runtime.dart';
import 'package:ai_connect_africa/features/projects/scaffold/project_scaffold.dart';
import 'package:ai_connect_africa/services/projects/project_manifest.dart';

const _html = '''
<!DOCTYPE html><html><head><title>T</title>
<style>body{color:red}</style><style>h1{margin:0}</style>
<script type="application/ld+json">{"@type":"Thing"}</script>
</head><body><h1 onclick="hi()">T</h1>
<form><input type="email"><textarea></textarea></form>
<script>function hi(){alert(1)}</script>
<script src="vendor.js"></script>
</body></html>
''';

/// Anything that would make a "fully offline" project reach the network.
final _externalUrl = RegExp(r'''(src|href)\s*=\s*["']https?://''', caseSensitive: false);

void main() {
  group('splitInlineAssets', () {
    test('moves inline CSS and classic JS out, keeps JSON-LD and src scripts', () {
      final split = splitInlineAssets(_html);
      expect(split.css, contains('body{color:red}'));
      expect(split.css, contains('h1{margin:0}'));
      expect(split.js, contains('function hi()'));
      expect(split.html, isNot(contains('<style')));
      expect(split.html, contains('application/ld+json'));
      expect(split.html, contains('src="vendor.js"'));
      expect('<link rel="stylesheet" href="css/styles.css">'.allMatches(split.html).length, 1);
    });
  });

  group('buildWebsiteProject', () {
    final files = buildWebsiteProject(title: 'Mama Bakery', html: _html, templateName: 'Bakery');

    test('has a runnable full-stack layout', () {
      for (final path in [
        'frontend/index.html',
        'frontend/css/styles.css',
        'frontend/js/main.js',
        'frontend/js/api.js',
        'frontend/js/contact.js',
        'frontend/js/config.js',
        'backend/requirements.txt',
        'backend/app/main.py',
        'backend/app/database.py',
        'backend/app/models.py',
        'backend/app/schemas.py',
        'backend/app/routes/contact.py',
        'backend/app/site.json',
        'backend/tests/test_api.py',
        'README.md',
        'DEPLOY.md',
        'Dockerfile',
        'render.yaml',
        '.gitignore',
        '.vscode/launch.json',
      ]) {
        expect(files.keys, contains(path), reason: path);
      }
    });

    test('page loads its split assets and the API scripts', () {
      final page = files['frontend/index.html']!;
      expect(page, contains('css/styles.css'));
      expect(page, contains('js/api.js'));
      expect(page, contains('js/contact.js'));
      expect(page, contains('src="js/main.js" defer'));
      expect(files['frontend/js/main.js'], contains('function hi()'));
    });

    test('adds no external URLs to the frontend', () {
      for (final e in files.entries.where((e) => e.key.startsWith('frontend/'))) {
        expect(_externalUrl.hasMatch(e.value), isFalse, reason: e.key);
      }
    });

    test('deploy guide covers free hosts for pages and API', () {
      final guide = files['DEPLOY.md']!;
      for (final host in ['GitHub Pages', 'Netlify', 'Render', 'Railway', 'PythonAnywhere', 'Docker']) {
        expect(guide, contains(host));
      }
      expect(guide, contains('mama-bakery'));
    });
  });

  group('buildAppProject', () {
    test('every app type gets CRUD routes and a matching data panel', () {
      for (final id in ['todo', 'notes', 'budget', 'quiz', 'farm', 'pos', 'unknown']) {
        final files = buildAppProject(title: 'App $id', html: _html, appTypeId: id);
        for (final r in resourcesForAppType(id)) {
          expect(files.keys, contains('backend/app/routes/${r.route}.py'), reason: id);
          expect(files['backend/app/main.py'], contains('${r.route}.router'), reason: id);
          expect(files['frontend/js/resources.js'], contains('"route": "${r.route}"'), reason: id);
          expect(files['backend/tests/test_api.py'], contains('test_${r.route}_crud'), reason: id);
        }
        expect(files['frontend/index.html'], contains('id="otic-data"'));
        expect(files['frontend/index.html'], contains('manifest.webmanifest'));
        expect(files.keys, containsAll(['frontend/sw.js', 'frontend/icon.svg']));
      }
    });

    test('unsafe theme colours fall back to a safe default', () {
      final files = buildAppProject(
          title: 'X', html: _html, appTypeId: 'todo', themeColor: 'red;}</style>');
      expect(files['frontend/manifest.webmanifest'], contains('#2563EB'));
    });
  });

  group('other kinds', () {
    test('Python Lab project runs main.py', () {
      final files = buildPythonProject(title: 'Calc', source: 'print(1)');
      expect(files['main.py'], 'print(1)\n');
      expect(files['README.md'], contains('python main.py'));
    });

    test('Web Dev Lab project is a static site', () {
      final files = buildStaticWebProject(title: 'Page', html: _html);
      expect(files.keys, containsAll(['index.html', 'css/styles.css', 'js/main.js', 'DEPLOY.md']));
      expect(files.keys.where((k) => k.startsWith('backend/')), isEmpty);
    });
  });

  group('manifest', () {
    test('round-trips through JSON', () {
      final m = ProjectManifest(
        id: 'p1',
        kind: ProjectKind.application,
        title: 'Budget',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 2),
        features: const ['Add expense'],
        answers: const {'app_name': 'Budget'},
        hasBackend: true,
      );
      final back = ProjectManifest.tryDecode(m.encode())!;
      expect(back.id, 'p1');
      expect(back.kind, ProjectKind.application);
      expect(back.features, ['Add expense']);
      expect(back.answers['app_name'], 'Budget');
      expect(back.hasBackend, isTrue);
      expect(back.updatedAt, DateTime(2026, 9, 2));
    });

    test('slugs are filesystem-safe', () {
      expect(projectSlug("Amina's Bakery & Café!"), 'aminas-bakery-caf');
      expect(projectSlug('  '), 'project');
      expect(projectSlug('a' * 80).length, lessThanOrEqualTo(48));
    });
  });
}
