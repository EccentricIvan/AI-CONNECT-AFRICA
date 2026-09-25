import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'model_locations.dart';
import 'model_runtime_policy.dart';

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

/// Locates the app's one reasoning model: **Qwen2.5-Coder-1.5B-Instruct**.
///
/// It does all reasoning and answer generation — tutoring, practice, paths
/// and code alike. The only other model on the device is the AfriSLM
/// translator (`AfriSlmModelManager`), which never answers questions.
///
/// One format per platform (see model_runtime_policy.dart):
/// - Android → LiteRT-LM `.litertlm` (int4), on NPU → GPU → LiteRT CPU.
/// - Windows / Linux → llama.cpp `.gguf`.
class ModelManager {
  /// Canonical desktop file — what Install Packages downloads and what the
  /// Windows release zip ships in `models/`.
  static const brainGgufFileName = 'qwen2.5-coder-1.5b-instruct.gguf';

  /// Canonical Android file (litert-community's int4 build, mirrored).
  static const brainLiteRtFileName = 'qwen2.5-coder-1.5b-instruct_int4.litertlm';

  /// This platform's canonical brain file.
  static String get brainFileName =>
      androidUsesLiteRt ? brainLiteRtFileName : brainGgufFileName;

  /// GGUF discovery order (every platform).
  static const ggufBrainFileNames = [
    brainGgufFileName,
    'qwen_coder_1.5b.Q4_K_M.gguf',
    'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
    'qwen2.5-coder-1.5b-q4.gguf',
  ];

  /// Android LiteRT names (canonical first).
  static const liteRtBrainFileNames = [
    brainLiteRtFileName,
    'Qwen2.5-Coder-1.5B-Instruct_int4.litertlm',
    'qwen_coder_1.5b.litertlm',
    'qwen2.5-coder-1.5b.litertlm',
    'qwen_coder_1.5b.literlm', // common typo in briefs
  ];

  /// Discovery order for the current platform — only the format this
  /// platform's runtime loads. A GGUF on Android (from an older build) is
  /// deliberately not "installed": Android runs LiteRT only.
  static List<String> brainFileNamesForPlatform() =>
      androidUsesLiteRt ? liteRtBrainFileNames : ggufBrainFileNames;

  // A Q4 1.5B is ~1 GB; anything under this is a truncated copy.
  static const _minSizeBytes = 400 * 1024 * 1024;

  Future<ModelInfo> checkModel() async {
    final names = brainFileNamesForPlatform();
    ModelInfo? truncated;
    for (final name in names) {
      final candidates = await _candidatePathsFor(name);
      debugPrint('BRAIN MODEL ($name) candidates:\n  ${candidates.join('\n  ')}');
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
            platform: _platformLabel(path),
          );
          continue;
        }
        return ModelInfo(
          status: ModelStatus.ready,
          path: path,
          sizeBytes: size,
          platform: _platformLabel(path),
        );
      }
    }
    return truncated ?? const ModelInfo(status: ModelStatus.notInstalled);
  }

  Future<List<String>> _candidatePathsFor(String fileName) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return modelCandidateFiles(fileName);
    }

    // Same discovery surface as desktop: canonical install + USB OTIC +
    // any documents/models aliases so HF Install Packages and USB share one
    // end-to-end path.
    final paths = <String>[
      ...await modelCandidateFiles(fileName),
      await canonicalModelInstallPath(fileName),
    ];
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
    final seen = <String>{};
    return [
      for (final path in paths)
        if (seen.add(p.normalize(path))) p.normalize(path),
    ];
  }

  String _platformLabel(String path) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android (LiteRT-LM · Qwen2.5-Coder 1.5B int4 · NPU/GPU/CPU)';
      case TargetPlatform.windows:
        return 'Windows (llama.cpp · Qwen2.5-Coder 1.5B GGUF · CPU)';
      case TargetPlatform.linux:
        return 'Linux (llama.cpp · Qwen2.5-Coder 1.5B GGUF · CPU)';
      default:
        return 'Unknown';
    }
  }

  /// Destination used when the user installs the model through the app.
  Future<String> installTargetPath() =>
      canonicalModelInstallPath(brainFileName, ensureDirectory: true);

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

    if (!isAllowedModelPath(sourcePath)) {
      throw ModelInstallException(
        'That is not the tutor package for this device.',
      );
    }

    final size = await source.length();
    if (size < _minSizeBytes) {
      throw const ModelInstallException(
        'That file is too small to be the tutor package — it should be about '
        '1 GB. The download or copy may be incomplete.',
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
          'Could not copy the package — the device may not have enough '
          'free storage (about 1.2 GB is needed).',
        );
      }
      rethrow;
    }
    return checkModel();
  }

  /// Where to tell the user to put the model files.
  Future<String> installInstructions() async {
    return 'Copy the learning packages to this device (from USB or the school '
        'server), then choose them with Install from file.';
  }

}
