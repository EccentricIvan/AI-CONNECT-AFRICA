import 'dart:convert';

/// Which Projects folder a creation lives in.
enum ProjectKind {
  website('Websites', 'Website'),
  application('Applications', 'Application'),
  python('Python', 'Python program'),
  guided('Guided', 'Guided project');

  const ProjectKind(this.folderName, this.label);

  /// Folder name on disk, e.g. `Websites`.
  final String folderName;

  /// Singular label, e.g. `Website`.
  final String label;

  static ProjectKind? fromFolderName(String name) {
    for (final k in values) {
      if (k.folderName.toLowerCase() == name.toLowerCase()) return k;
    }
    return null;
  }

  static ProjectKind fromName(String? name, {ProjectKind fallback = ProjectKind.website}) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return fallback;
  }
}

/// `otic-project.json` — written into every project folder.
///
/// The folder on disk is the source of truth (a student can copy or delete
/// it in Explorer); this file only says what the app made and how to reopen
/// it in the builder.
class ProjectManifest {
  ProjectManifest({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.source = '',
    this.template = '',
    this.templateName = '',
    this.features = const [],
    this.answers = const {},
    this.hasBackend = false,
    this.exportedAt,
  });

  static const fileName = 'otic-project.json';
  static const formatVersion = 1;

  final String id;
  final ProjectKind kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Which builder made it: `site_builder`, `app_builder`, `web_lab`, …
  final String source;
  final String template;
  final String templateName;
  final List<String> features;
  final Map<String, String> answers;
  final bool hasBackend;
  final DateTime? exportedAt;

  static String newId() => 'p${DateTime.now().microsecondsSinceEpoch}';

  ProjectManifest copyWith({
    String? id,
    ProjectKind? kind,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? exportedAt,
  }) =>
      ProjectManifest(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        source: source,
        template: template,
        templateName: templateName,
        features: features,
        answers: answers,
        hasBackend: hasBackend,
        exportedAt: exportedAt ?? this.exportedAt,
      );

  Map<String, Object?> toJson() => {
        'format': formatVersion,
        'id': id,
        'kind': kind.name,
        'title': title,
        'source': source,
        'template': template,
        'templateName': templateName,
        'features': features,
        'answers': answers,
        'hasBackend': hasBackend,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'exportedAt': exportedAt?.toIso8601String(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Null when [raw] is not a manifest this app can read.
  static ProjectManifest? tryDecode(String raw, {ProjectKind? kindHint}) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      DateTime date(Object? v) =>
          v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
      return ProjectManifest(
        id: (j['id'] as String?) ?? newId(),
        kind: ProjectKind.fromName(j['kind'] as String?,
            fallback: kindHint ?? ProjectKind.website),
        title: (j['title'] as String?) ?? 'Untitled',
        source: (j['source'] as String?) ?? '',
        template: (j['template'] as String?) ?? '',
        templateName: (j['templateName'] as String?) ?? '',
        features: [
          for (final f in (j['features'] as List?) ?? const []) '$f',
        ],
        answers: {
          for (final e in ((j['answers'] as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}',
        },
        hasBackend: j['hasBackend'] == true,
        createdAt: date(j['createdAt']),
        updatedAt: date(j['updatedAt']),
        exportedAt: j['exportedAt'] is String
            ? DateTime.tryParse(j['exportedAt'] as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Folder-name form of a title: lowercase, dashes, safe on every filesystem.
String projectSlug(String title, {String fallback = 'project'}) {
  final s = title
      .toLowerCase()
      .replaceAll(RegExp(r"[’']"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (s.isEmpty) return fallback;
  return s.length > 48 ? s.substring(0, 48).replaceAll(RegExp(r'-$'), '') : s;
}
