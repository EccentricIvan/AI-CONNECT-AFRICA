import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_manifest.dart';

/// Whether a model file is the one its release published.
enum ModelVerification {
  /// Its SHA-256 matches its manifest.
  verified,

  /// It has a known file name but different bytes: corrupted, or swapped.
  mismatch,

  /// Not a file this build has a manifest for.
  unknown,
}

/// Checks model files against their manifests' SHA-256. Hashing a 1 GB
/// file takes a while on a phone, so a result is remembered per path,
/// size and modified time, and a changed file is checked again.
class ModelVerifier {
  ModelVerifier({ModelRegistry registry = const ModelRegistry()})
    : _registry = registry;

  final ModelRegistry _registry;

  static const _prefix = 'model_verify:';

  /// The remembered result for [path], or null when it hasn't been checked
  /// in its current state.
  Future<ModelVerification?> cached(String path) async {
    final stamp = await _stamp(path);
    if (stamp == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_prefix$path');
    if (saved == null) return null;
    final i = saved.lastIndexOf('|');
    if (i < 0 || saved.substring(0, i) != stamp) return null;
    return ModelVerification.values.asNameMap()[saved.substring(i + 1)];
  }

  /// Hashes [path] (off the UI isolate) and remembers the result.
  Future<ModelVerification> verify(String path) async {
    final manifest = _registry.forFile(path);
    if (manifest == null) return ModelVerification.unknown;
    final stamp = await _stamp(path);
    if (stamp == null) return ModelVerification.unknown;
    final digest = await Isolate.run(() => _sha256Of(path));
    final result = digest == manifest.sha256
        ? ModelVerification.verified
        : ModelVerification.mismatch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$path', '$stamp|${result.name}');
    return result;
  }

  /// Verifies [path] once, later, unless it already was — so the first
  /// launch isn't slowed while the model loads.
  void verifyLater(String path, {Duration delay = const Duration(minutes: 1)}) {
    unawaited(
      Future<void>.delayed(delay, () async {
        if (await cached(path) != null) return;
        final result = await verify(path);
        debugPrint('MODEL VERIFY $path: ${result.name}');
      }).catchError((Object e) => debugPrint('MODEL VERIFY failed: $e')),
    );
  }

  /// Whether a model manager should refuse [path]: its bytes are known not
  /// to match its release.
  Future<bool> isKnownBad(String path) async {
    try {
      return await cached(path) == ModelVerification.mismatch;
    } catch (_) {
      return false; // no preferences store: nothing remembered
    }
  }

  static Future<String?> _stamp(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return '${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  static Future<String> _sha256Of(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
}
