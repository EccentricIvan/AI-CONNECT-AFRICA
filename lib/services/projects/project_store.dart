import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../ai_core/model/model_locations.dart';
import 'project_manifest.dart';

export 'project_manifest.dart';

/// One project folder as found on disk.
class ProjectFolder {
  const ProjectFolder({
    required this.directory,
    required this.manifest,
    required this.fileCount,
    required this.sizeBytes,
    required this.hasManifestFile,
  });

  final Directory directory;
  final ProjectManifest manifest;
  final int fileCount;
  final int sizeBytes;

  /// False for a folder the student dropped in by hand (no manifest yet).
  final bool hasManifestFile;

  String get path => directory.path;
  String get folderName => p.basename(directory.path);
  ProjectKind get kind => manifest.kind;
  String get title => manifest.title;
}

/// Creations saved as real folders:
///
/// `<root>/<learner>-<id>/<Websites|Applications|Python|Guided>/<project>/`
///
/// * Windows / Linux: `<Documents>/OTIC/Projects` — the student can open it
///   in Explorer or VS Code directly.
/// * Android: `<app documents>/projects` — private to the app, so the
///   Projects screen exports zips instead.
///
/// The disk is the source of truth: a folder cut or deleted in Explorer is
/// simply gone next time [list] runs, and a folder pasted in shows up.
class ProjectStore {
  ProjectStore({Future<Directory> Function()? root}) : _root = root ?? defaultRoot;

  final Future<Directory> Function() _root;

  static Future<Directory> defaultRoot() async {
    final base = await resolveAppStorageDirectory();
    final dir = defaultTargetPlatform == TargetPlatform.android
        ? Directory(p.join(base.path, 'projects'))
        : Directory(p.join(base.path, 'OTIC', 'Projects'));
    await dir.create(recursive: true);
    return dir;
  }

  /// True where the Projects folder is visible to Explorer / VS Code.
  static bool get foldersAreUserVisible =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // ── Learner folder ────────────────────────────────────────────────────────

  /// `<name>-<id>`. Matched by the `-<id>` suffix, so renaming a learner
  /// never orphans their projects.
  Future<Directory> learnerDirectory(int studentId, {String? studentName}) async {
    final root = await _root();
    await root.create(recursive: true);
    final suffix = '-$studentId';
    await for (final e in root.list(followLinks: false)) {
      if (e is Directory) {
        final name = p.basename(e.path);
        if (name == '$studentId' || name.endsWith(suffix)) return e;
      }
    }
    final slug = projectSlug(studentName ?? '', fallback: 'learner');
    final dir = Directory(p.join(root.path, '$slug$suffix'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Removes everything a learner saved (used by LearnerDataWiper).
  Future<void> deleteLearner(int studentId) async {
    final root = await _root();
    if (!await root.exists()) return;
    final suffix = '-$studentId';
    await for (final e in root.list(followLinks: false)) {
      if (e is Directory) {
        final name = p.basename(e.path);
        if (name == '$studentId' || name.endsWith(suffix)) {
          await e.delete(recursive: true);
        }
      }
    }
  }

  Future<Directory> kindDirectory(int studentId, ProjectKind kind,
      {String? studentName}) async {
    final learner = await learnerDirectory(studentId, studentName: studentName);
    final dir = Directory(p.join(learner.path, kind.folderName));
    await dir.create(recursive: true);
    return dir;
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<ProjectFolder>> list(int studentId) async {
    final learner = await learnerDirectory(studentId);
    final out = <ProjectFolder>[];
    await for (final kindDir in learner.list(followLinks: false)) {
      if (kindDir is! Directory) continue;
      final kind = ProjectKind.fromFolderName(p.basename(kindDir.path));
      if (kind == null) continue;
      await for (final projectDir in kindDir.list(followLinks: false)) {
        if (projectDir is! Directory) continue;
        if (p.basename(projectDir.path).startsWith('.')) continue;
        final folder = await read(projectDir, kindHint: kind);
        if (folder != null) out.add(folder);
      }
    }
    out.sort((a, b) => b.manifest.updatedAt.compareTo(a.manifest.updatedAt));
    return out;
  }

  /// Reads one project folder. The folder it sits in decides the kind, so a
  /// project moved between category folders in Explorer is shown where it
  /// now is.
  Future<ProjectFolder?> read(Directory dir, {ProjectKind? kindHint}) async {
    if (!await dir.exists()) return null;
    final kind = kindHint ??
        ProjectKind.fromFolderName(p.basename(dir.parent.path)) ??
        ProjectKind.website;
    final manifestFile = File(p.join(dir.path, ProjectManifest.fileName));
    ProjectManifest? manifest;
    final hasManifest = await manifestFile.exists();
    if (hasManifest) {
      manifest = ProjectManifest.tryDecode(await manifestFile.readAsString(),
          kindHint: kind);
    }
    final stat = await dir.stat();
    manifest ??= ProjectManifest(
      id: 'folder:${p.basename(dir.path)}',
      kind: kind,
      title: p.basename(dir.path),
      createdAt: stat.modified,
      updatedAt: stat.modified,
    );
    if (manifest.kind != kind) manifest = manifest.copyWith(kind: kind);

    var count = 0;
    var size = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && p.basename(e.path) != ProjectManifest.fileName) {
        count++;
        size += await e.length();
      }
    }
    return ProjectFolder(
      directory: dir,
      manifest: manifest,
      fileCount: count,
      sizeBytes: size,
      hasManifestFile: hasManifest,
    );
  }

  Future<ProjectFolder?> findById(int studentId, String id) async {
    for (final f in await list(studentId)) {
      if (f.manifest.id == id) return f;
    }
    return null;
  }

  /// Every file in the project, relative path → File, sorted.
  Future<List<(String, File)>> files(ProjectFolder folder) async {
    final out = <(String, File)>[];
    await for (final e in folder.directory.list(recursive: true, followLinks: false)) {
      if (e is File) {
        out.add((p.relative(e.path, from: folder.path).replaceAll('\\', '/'), e));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Creates or updates a project.
  ///
  /// With [projectId] of an existing project the same folder is rewritten
  /// (files the student added by hand are kept). Each file is written to a
  /// `.part` sibling and renamed, so a crash never leaves half a file.
  Future<ProjectFolder> save({
    required int studentId,
    String? studentName,
    required ProjectKind kind,
    required String title,
    required Map<String, String> files,
    Map<String, Uint8List> binaryFiles = const {},
    String? projectId,
    String source = '',
    String template = '',
    String templateName = '',
    List<String> features = const [],
    Map<String, String> answers = const {},
    bool? hasBackend,
  }) async {
    final existing = projectId == null ? null : await findById(studentId, projectId);
    final now = DateTime.now();
    final Directory dir;
    if (existing != null) {
      dir = existing.directory;
    } else {
      final parent = await kindDirectory(studentId, kind, studentName: studentName);
      dir = await _uniqueDir(parent, projectSlug(title));
    }
    await dir.create(recursive: true);

    for (final e in files.entries) {
      await _writeAtomic(dir, e.key, text: e.value);
    }
    for (final e in binaryFiles.entries) {
      await _writeAtomic(dir, e.key, bytes: e.value);
    }

    final manifest = ProjectManifest(
      id: existing?.manifest.id ?? projectId ?? ProjectManifest.newId(),
      kind: existing?.kind ?? kind,
      title: title,
      source: source,
      template: template,
      templateName: templateName,
      features: features,
      answers: answers,
      hasBackend: hasBackend ?? files.keys.any((k) => k.startsWith('backend/')),
      createdAt: existing?.manifest.createdAt ?? now,
      updatedAt: now,
      exportedAt: existing?.manifest.exportedAt,
    );
    await _writeAtomic(dir, ProjectManifest.fileName, text: manifest.encode());
    return (await read(dir))!;
  }

  /// Adds (or replaces) files in an existing project without touching the
  /// rest — e.g. an image the student picked.
  Future<void> addFiles(ProjectFolder folder,
      {Map<String, String> files = const {},
      Map<String, Uint8List> binaryFiles = const {}}) async {
    for (final e in files.entries) {
      await _writeAtomic(folder.directory, e.key, text: e.value);
    }
    for (final e in binaryFiles.entries) {
      await _writeAtomic(folder.directory, e.key, bytes: e.value);
    }
    await _touch(folder);
  }

  Future<ProjectFolder> rename(ProjectFolder folder, String newTitle) async {
    final title = newTitle.trim().isEmpty ? folder.title : newTitle.trim();
    var dir = folder.directory;
    final wanted = projectSlug(title);
    if (wanted != folder.folderName) {
      final target = await _uniqueDir(dir.parent, wanted);
      dir = await dir.rename(target.path);
    }
    await _writeManifest(dir, folder.manifest.copyWith(title: title, updatedAt: DateTime.now()));
    return (await read(dir))!;
  }

  /// Copy → a new project with a new id, in [kind] (default: same folder).
  Future<ProjectFolder> duplicate(ProjectFolder folder, int studentId,
      {ProjectKind? kind}) async {
    final targetKind = kind ?? folder.kind;
    final parent = await kindDirectory(studentId, targetKind);
    final title = '${folder.title} (copy)';
    final target = await _uniqueDir(parent, projectSlug(title));
    await copyDirectory(folder.directory, target);
    final now = DateTime.now();
    await _writeManifest(
      target,
      ProjectManifest(
        id: ProjectManifest.newId(),
        kind: targetKind,
        title: title,
        source: folder.manifest.source,
        template: folder.manifest.template,
        templateName: folder.manifest.templateName,
        features: folder.manifest.features,
        answers: folder.manifest.answers,
        hasBackend: folder.manifest.hasBackend,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (await read(target, kindHint: targetKind))!;
  }

  /// Cut → paste into another category folder.
  Future<ProjectFolder> moveToKind(ProjectFolder folder, int studentId,
      ProjectKind kind) async {
    if (kind == folder.kind) return folder;
    final parent = await kindDirectory(studentId, kind);
    final target = await _uniqueDir(parent, folder.folderName);
    Directory moved;
    try {
      moved = await folder.directory.rename(target.path);
    } on FileSystemException {
      // Rename across volumes / locked folder: copy then delete.
      await copyDirectory(folder.directory, target);
      await folder.directory.delete(recursive: true);
      moved = target;
    }
    await _writeManifest(moved, folder.manifest.copyWith(kind: kind, updatedAt: DateTime.now()));
    return (await read(moved, kindHint: kind))!;
  }

  Future<void> delete(ProjectFolder folder) async {
    if (await folder.directory.exists()) {
      await folder.directory.delete(recursive: true);
    }
  }

  /// Zip of the project, with the project folder as the zip's top folder.
  /// The app's own manifest is left out — it means nothing outside the app.
  Future<Uint8List> exportZip(ProjectFolder folder) async {
    final archive = Archive();
    for (final (rel, file) in await files(folder)) {
      if (rel == ProjectManifest.fileName) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile('${folder.folderName}/$rel', bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Desktop "Copy to…": copies the folder into [destination]. Returns the
  /// new folder's path.
  Future<String> exportToDirectory(ProjectFolder folder, String destination) async {
    final target = await _uniqueDir(Directory(destination), folder.folderName);
    await copyDirectory(folder.directory, target, skip: {ProjectManifest.fileName});
    return target.path;
  }

  Future<ProjectFolder> markExported(ProjectFolder folder) async {
    final now = DateTime.now();
    await _writeManifest(folder.directory, folder.manifest.copyWith(exportedAt: now));
    return (await read(folder.directory, kindHint: folder.kind))!;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _touch(ProjectFolder folder) =>
      _writeManifest(folder.directory, folder.manifest.copyWith(updatedAt: DateTime.now()));

  Future<void> _writeManifest(Directory dir, ProjectManifest m) =>
      _writeAtomic(dir, ProjectManifest.fileName, text: m.encode());

  Future<void> _writeAtomic(Directory dir, String relPath,
      {String? text, List<int>? bytes}) async {
    final clean = relPath.replaceAll('\\', '/');
    if (clean.split('/').any((s) => s == '..') || p.isAbsolute(clean)) {
      throw ArgumentError('Unsafe project path: $relPath');
    }
    final target = File(p.joinAll([dir.path, ...clean.split('/')]));
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    if (text != null) {
      await part.writeAsString(text, flush: true);
    } else {
      await part.writeAsBytes(bytes ?? const [], flush: true);
    }
    try {
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } on FileSystemException {
      // File open in an editor (Windows locks it): write in place instead.
      if (text != null) {
        await target.writeAsString(text, flush: true);
      } else {
        await target.writeAsBytes(bytes ?? const [], flush: true);
      }
      if (await part.exists()) await part.delete();
    }
  }

  Future<Directory> _uniqueDir(Directory parent, String slug) async {
    await parent.create(recursive: true);
    var candidate = Directory(p.join(parent.path, slug));
    var n = 2;
    while (await candidate.exists()) {
      candidate = Directory(p.join(parent.path, '$slug-$n'));
      n++;
    }
    return candidate;
  }
}

/// Recursive copy. [skip] names files (basename) to leave out.
Future<void> copyDirectory(Directory from, Directory to,
    {Set<String> skip = const {}}) async {
  await to.create(recursive: true);
  await for (final e in from.list(recursive: false, followLinks: false)) {
    final name = p.basename(e.path);
    if (skip.contains(name)) continue;
    if (e is Directory) {
      await copyDirectory(e, Directory(p.join(to.path, name)), skip: skip);
    } else if (e is File) {
      await e.copy(p.join(to.path, name));
    }
  }
}
