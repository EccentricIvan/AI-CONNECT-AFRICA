import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// User-writable folder for the DB and USB-installed models.
///
/// [getApplicationDocumentsDirectory] can throw on Windows (broken OneDrive
/// known folder, or the plugin answering before it is ready). Fall back to
/// `%USERPROFILE%\Documents` so chat is not blocked by that plugin call.
Future<Directory> resolveAppStorageDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (e) {
    debugPrint('app storage: path_provider failed: $e');
  }
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final docs = Directory(p.join(home, 'Documents'));
    try {
      if (!await docs.exists()) await docs.create(recursive: true);
      return docs;
    } catch (e) {
      debugPrint('app storage: Documents fallback failed: $e');
    }
  }
  final local = Directory(p.join(Directory.current.path, 'OTIC'));
  await local.create(recursive: true);
  return local;
}

/// Folders that may contain Qwen / AfriSLM GGUF files.
///
/// Documents/OTIC is the install target, but a Release zip (and this repo's
/// `dist/models` / `build/.../Debug/models`) keeps the files next to the
/// exe. Flutter also copies `assets/models/` next to the Debug exe.
Future<List<String>> modelCandidateFiles(String fileName) async {
  final seen = <String>{};
  final out = <String>[];

  void addFile(String path) {
    final n = p.normalize(path);
    if (seen.add(n)) out.add(n);
  }

  void addDir(String? dir) {
    if (dir == null || dir.isEmpty) return;
    addFile(p.join(dir, fileName));
    addFile(p.join(dir, 'models', fileName));
    addFile(p.join(dir, 'OTIC', fileName));
    addFile(p.join(dir, 'dist', 'models', fileName));
    addFile(p.join(dir, 'assets', 'models', fileName));
  }

  try {
    addDir((await resolveAppStorageDirectory()).path);
  } catch (e) {
    debugPrint('model_locations: documents dir failed: $e');
  }

  try {
    final exe = p.dirname(Platform.resolvedExecutable);
    addDir(exe);
    addDir(p.join(exe, 'data', 'flutter_assets', 'assets'));
  } catch (e) {
    debugPrint('model_locations: exe dir failed: $e');
  }

  try {
    addDir(Directory.current.path);
  } catch (_) {}

  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    addDir(p.join(home, 'Documents'));
    addDir(p.join(home, 'Documents', 'OTIC'));
    addDir(p.join(home, 'OneDrive', 'Documents'));
    addDir(p.join(home, 'OneDrive', 'Documents', 'OTIC'));
  }

  return out;
}

/// Canonical install path: Android app files /models, else Documents/OTIC.
Future<String> canonicalModelInstallPath(
  String fileName, {
  bool ensureDirectory = false,
}) async {
  late final String dir;
  final root = await resolveAppStorageDirectory();
  if (defaultTargetPlatform == TargetPlatform.android) {
    dir = p.join(root.path, 'models');
  } else {
    dir = p.join(root.path, 'OTIC');
  }
  if (ensureDirectory) {
    await Directory(dir).create(recursive: true);
  }
  return p.join(dir, fileName);
}
