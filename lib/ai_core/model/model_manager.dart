import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'model_locations.dart';

enum ModelStatus {
  /// Model file found and ready to load.
  ready,

  /// No model file present — user must transfer via USB.
  notInstalled,

  /// Model file exists but is corrupted (wrong size / bad header).
  corrupted,
}

/// A user-facing problem while installing a model from a picked file.
class ModelInstallException implements Exception {
  const ModelInstallException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ModelInfo {
  const ModelInfo({
    required this.status,
    this.path,
    this.sizeBytes,
    this.platform,
  });

  final ModelStatus status;
  final String? path;
  final int? sizeBytes;
  final String? platform;

  bool get isReady => status == ModelStatus.ready;
}

/// Locates the Qwen3-0.6B tutor brain.
///
/// Canonical file: [qwenGgufFileName] (`qwen-0.6b-instruct.gguf`).
/// That GGUF is the general reasoning brain. LiteRT (`chat-model.litertlm`)
/// is only a fallback if the GGUF is missing.
class ModelManager {
  /// General tutor brain — Qwen 0.6B Instruct GGUF.
  static const qwenGgufFileName = 'qwen-0.6b-instruct.gguf';

  /// LiteRT copy used by the Android APK bundle and as a GGUF fallback.
  static const chatModelFileName = 'chat-model.litertlm';

  /// Alternate names: other GGUF dumps, then the LiteRT file.
  static const alternateChatFileNames = [
    qwenGgufFileName,
    'Qwen3-0.6B-Q4_K_M.gguf',
    'Qwen3-0.6B-Instruct-Q4_K_M.gguf',
    'qwen3-0.6b-instruct.gguf',
    'qwen-0.6b.gguf',
    'chat-model.gguf',
    chatModelFileName,
  ];

  /// Marks a [ModelInfo.path] that is not a filesystem path at all but the
  /// model sitting inside the APK's own `assets/models/` folder.
  static const bundledAssetPrefix = 'bundled:';

  /// Path value handed to the engine when the chat model is served straight
  /// out of the APK.
  static const bundledChatModelPath = '$bundledAssetPrefix$chatModelFileName';
  // Smallest supported AfriSLM GGUF (Q4_K_M) is ~500 MB; reject truncations.
  static const _minSizeBytes = 250 * 1024 * 1024; // 250 MB

  Future<ModelInfo> checkModel() async {
    final names = [...alternateChatFileNames];
    ModelInfo? truncated;
    for (final name in names) {
      final candidates = await _candidatePathsFor(name);
      debugPrint('CHAT MODEL ($name) candidates:\n  ${candidates.join('\n  ')}');
      for (final path in candidates) {
        final file = File(path);
        try {
          if (!await file.exists()) continue;
        } catch (_) {
          continue;
        }
        final size = await file.length();
        if (size < _minSizeBytes) {
          truncated ??= ModelInfo(
            status: ModelStatus.corrupted,
            path: path,
            sizeBytes: size,
            platform: _platformLabel,
          );
          continue;
        }
        return ModelInfo(
          status: ModelStatus.ready,
          path: path,
          sizeBytes: size,
          platform: _platformLabel,
        );
      }
    }
    return truncated ?? const ModelInfo(status: ModelStatus.notInstalled);
  }

  Future<List<String>> _candidatePathsFor(String fileName) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return modelCandidateFiles(fileName);
    }

    final paths = <String>[];
    paths.add(await canonicalModelInstallPath(fileName));
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        paths.add(
          p.join(
            ext.parent.parent.parent.parent.path,
            'OTIC',
            fileName,
          ),
        );
      }
    } catch (_) {}
    return paths;
  }

  String get _platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android (llama.cpp · Qwen 0.6B)';
      case TargetPlatform.windows:
        return 'Windows (llama.cpp · Qwen 0.6B)';
      case TargetPlatform.linux:
        return 'Linux (llama.cpp · Qwen 0.6B)';
      default:
        return 'Unknown';
    }
  }

  /// Destination used when the user installs a model through the app.
  Future<String> installTargetPath() async {
    return canonicalModelInstallPath(qwenGgufFileName, ensureDirectory: true);
  }

  /// Copies a user-picked model file into the expected location.
  ///
  /// Validates extension and size first, copies to a `.part` file and
  /// renames on success so an interrupted copy is never mistaken for a
  /// valid model. Reports progress as 0..1 through [onProgress].
  Future<ModelInfo> installFromFile(
    String sourcePath, {
    void Function(double progress)? onProgress,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const ModelInstallException('The selected file no longer exists.');
    }

    final ext = p.extension(sourcePath).toLowerCase();
    if (ext != '.litertlm' && ext != '.gguf') {
      throw const ModelInstallException(
        'Wrong file type. The tutor brain is qwen-0.6b-instruct.gguf '
        '(or a Qwen instruct .gguf).',
      );
    }

    final size = await source.length();
    if (size < _minSizeBytes) {
      throw const ModelInstallException(
        'That file is too small to be the chat model — it should be at '
        'least a few hundred MB. The download or copy may be incomplete.',
      );
    }

    final targetPath = await installTargetPath();
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    final partial = File('$targetPath.part');
    final sink = partial.openWrite();
    var copied = 0;
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copied += chunk.length;
        onProgress?.call(copied / size);
      }
      await sink.flush();
      await sink.close();
      if (await target.exists()) await target.delete();
      await partial.rename(targetPath);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await partial.exists()) await partial.delete();
      if (e is FileSystemException) {
        throw const ModelInstallException(
          'Could not copy the model — the device may not have enough '
          'free storage (about 1 GB is needed).',
        );
      }
      rethrow;
    }
    return checkModel();
  }

  /// Where to tell the user to put the model file.
  Future<String> installInstructions() async {
    return 'Transfer the model file to this device, then choose it with '
        'Install from file.\n\n'
        'Tutor brain: Qwen 0.6B GGUF\n'
        '  models\\qwen-0.6b-instruct.gguf\n'
        '  Documents\\OTIC\\qwen-0.6b-instruct.gguf\n\n'
        'Programming brain: Qwen 1.5B Coder GGUF\n'
        '  models\\qwen2.5-coder-1.5b-instruct.gguf\n\n'
        'Translator: AfriSLM 0.8B GGUF\n'
        '  models\\afrislm-0.8b-q4_k_m.gguf';
  }
}
