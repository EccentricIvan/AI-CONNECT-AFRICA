import 'dart:typed_data';

import '../../../services/projects/project_manifest.dart';
import '../../../shared/coding/html_images.dart';
import 'frontend_runtime.dart';
import 'project_docs.dart';
import 'python_backend.dart';
import 'resource_spec.dart';

export 'resource_spec.dart' show resourcesForAppType;

/// Relative path → file contents for one generated project.
typedef ProjectFiles = Map<String, String>;

String _themeOr(String? hex) =>
    (hex != null && RegExp(r'^#[0-9a-fA-F]{3,8}$').hasMatch(hex)) ? hex : '#2563EB';

/// Splits [html] into page / CSS / JS and pulls embedded pictures out into
/// `<imagesDir>/…` files (added to [images], keyed by project path).
/// [pageDir] is where index.html lives (`frontend` or the root).
SplitHtml _splitWithImages(
  String html, {
  required String pageDir,
  Map<String, Uint8List>? images,
}) {
  final split = splitInlineAssets(html);
  final page = extractImages(split.html, folder: 'images', namePrefix: 'picture');
  final css = extractImages(split.css, folder: '../images', namePrefix: 'background');
  final js = extractImages(split.js, folder: 'images', namePrefix: 'script-image');
  final prefix = pageDir.isEmpty ? '' : '$pageDir/';
  for (final m in [page.files, css.files, js.files]) {
    for (final e in m.entries) {
      images?['${prefix}images/${e.key}'] = e.value;
    }
  }
  return SplitHtml(html: page.text, css: css.text, js: js.text);
}

ProjectFiles _sharedFullStackFiles(String title) {
  final slug = projectSlug(title);
  return {
    'DEPLOY.md': deployGuide(title: title, slug: slug),
    'Dockerfile': kDockerfile,
    '.dockerignore': kDockerignore,
    'render.yaml': renderYaml(slug),
    '.gitignore': kFullStackGitignore,
    '.vscode/extensions.json': kVsCodeExtensions,
    '.vscode/launch.json': kVsCodeLaunch,
  };
}

/// Website (Build a Website tab): the assembled page split into
/// `frontend/` files, a FastAPI backend that stores contact-form messages and
/// serves the site's own text at `/api/site`, plus docs and deploy configs.
ProjectFiles buildWebsiteProject({
  required String title,
  required String html,
  String templateName = '',
  Map<String, String> siteContent = const {},
  Map<String, Uint8List>? images,
}) {
  final split = _splitWithImages(html, pageDir: 'frontend', images: images);
  var page = split.html;
  if (split.css.isEmpty) {
    page = injectIntoHead(page, '<link rel="stylesheet" href="css/styles.css">');
  }
  page = injectBeforeBodyEnd(
    page,
    '<script src="js/config.js"></script>\n'
    '<script src="js/api.js"></script>\n'
    '<script src="js/contact.js"></script>\n'
    '<script src="js/main.js" defer></script>',
  );

  const resources = [kContactMessageResource];
  return {
    'frontend/index.html': page,
    'frontend/css/styles.css': split.css.isEmpty
        ? '/* Styles for $title */\n'
        : '/* Styles for $title */\n${split.css}',
    'frontend/js/main.js': split.js.isEmpty
        ? '// Page behaviour for $title.\n'
        : '// Page behaviour for $title.\n\n${split.js}',
    'frontend/js/config.js': kConfigJs,
    'frontend/js/api.js': kApiJs,
    'frontend/js/contact.js': kContactJs,
    ...buildPythonBackend(
      title: title,
      resources: resources,
      publicSubmissions: true,
      siteContent: {
        'title': title,
        if (templateName.isNotEmpty) 'template': templateName,
        ...siteContent,
      },
    ),
    'README.md': fullStackReadme(
      title: title,
      kindLabel: templateName.isEmpty ? 'Website' : '$templateName website',
      resources: resources,
      description: 'Visitors can send you messages through the contact form; '
          'the backend stores them at `/api/contact`.',
    ),
    ..._sharedFullStackFiles(title),
  };
}

/// Application (App chat builder / App Dev Lab): the built screen as the
/// frontend, a data panel wired to a CRUD backend for the app type's
/// resources, installable as a PWA, plus docs and deploy configs.
ProjectFiles buildAppProject({
  required String title,
  required String html,
  required String appTypeId,
  String appTypeName = '',
  String? themeColor,
  List<String> features = const [],
  Map<String, Uint8List>? images,
}) {
  final theme = _themeOr(themeColor);
  final resources = resourcesForAppType(appTypeId);
  final split = _splitWithImages(html, pageDir: 'frontend', images: images);
  var page = split.html;
  final head = StringBuffer()
    ..writeln('<link rel="manifest" href="manifest.webmanifest">')
    ..writeln('<meta name="theme-color" content="$theme">')
    ..writeln('<link rel="icon" href="icon.svg" type="image/svg+xml">');
  if (split.css.isEmpty) {
    head.writeln('<link rel="stylesheet" href="css/styles.css">');
  }
  head.write('<link rel="stylesheet" href="css/data.css">');
  page = injectIntoHead(page, head.toString());
  page = injectBeforeBodyEnd(
    page,
    '<section id="otic-data" class="otic-data" aria-label="App data"></section>\n'
    '<script src="js/config.js"></script>\n'
    '<script src="js/api.js"></script>\n'
    '<script src="js/resources.js"></script>\n'
    '<script src="js/data.js"></script>\n'
    '<script src="js/main.js" defer></script>'
    '$kRegisterServiceWorker',
  );

  final featureLine = features.isEmpty ? '' : 'Features: ${features.join(', ')}.';
  return {
    'frontend/index.html': page,
    'frontend/css/styles.css': '/* Styles for $title */\n${split.css}',
    'frontend/css/data.css': kDataPanelCss,
    'frontend/js/main.js': split.js.isEmpty
        ? '// Screen behaviour for $title.\n'
        : '// Screen behaviour for $title.\n\n${split.js}',
    'frontend/js/config.js': kConfigJs,
    'frontend/js/api.js': kApiJs,
    'frontend/js/resources.js': resourcesJs(resources),
    'frontend/js/data.js': kDataPanelJs,
    'frontend/manifest.webmanifest': webManifest(title: title, themeColor: theme),
    'frontend/icon.svg': appIconSvg(theme, title),
    'frontend/sw.js': kServiceWorkerJs,
    ...buildPythonBackend(title: title, resources: resources),
    'README.md': fullStackReadme(
      title: title,
      kindLabel: appTypeName.isEmpty ? 'App' : '$appTypeName app',
      resources: resources,
      description: [
        featureLine,
        'Installable on a phone: open it in Chrome over `https` and choose '
            '**Add to Home screen**.',
      ].where((s) => s.isNotEmpty).join('\n\n'),
    ),
    ..._sharedFullStackFiles(title),
  };
}

/// Web Dev Lab: the student's own HTML/CSS/JS as a static site.
ProjectFiles buildStaticWebProject({
  required String title,
  required String html,
  Map<String, Uint8List>? images,
}) {
  final split = _splitWithImages(html, pageDir: '', images: images);
  var page = split.html;
  if (split.js.isNotEmpty) {
    page = injectBeforeBodyEnd(page, '<script src="js/main.js" defer></script>');
  }
  return {
    'index.html': page,
    if (split.css.isNotEmpty) 'css/styles.css': split.css,
    if (split.js.isNotEmpty) 'js/main.js': split.js,
    'README.md': '# $title\n\nA web page made in the AI Connect Africa **Web Dev Lab**.\n\n'
        'Open `index.html` in a browser, or open this folder in VS Code.\n'
        'To put it online see `DEPLOY.md`.\n',
    'DEPLOY.md': staticDeployGuide(title: title, slug: projectSlug(title)),
  };
}

/// Python Lab: the program as `main.py`.
ProjectFiles buildPythonProject({
  required String title,
  required String source,
}) {
  return {
    'main.py': source.endsWith('\n') ? source : '$source\n',
    'requirements.txt': '# Add any packages this program needs, one per line.\n',
    'README.md': pythonReadme(title: title, mainFile: 'main.py'),
    '.gitignore': kPythonGitignore,
    '.vscode/launch.json': kVsCodePythonLaunch,
  };
}

/// Guided project (essay, business plan…): the conversation as Markdown.
ProjectFiles buildGuidedProject({
  required String title,
  required String projectType,
  required String topic,
  required List<({String role, String text})> steps,
}) {
  final buf = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('*${projectType.replaceAll('_', ' ')} · $topic*')
    ..writeln();
  for (final s in steps) {
    buf
      ..writeln(s.role == 'user' ? '**Me:** ${s.text}' : '**Mentor:** ${s.text}')
      ..writeln();
  }
  return {'README.md': buf.toString()};
}
