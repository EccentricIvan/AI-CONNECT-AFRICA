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

/// Locates the app's one reasoning model: **Qwen2.5-Coder-1.5B-Instruct**.
///
/// It does all reasoning and answer generation — tutoring, practice, paths
/// and code alike. The only other model on the device is the AfriSLM
/// translator (`AfriSlmModelManager`), which never answers questions.
///
/// - Windows / Linux / Android → llama.cpp GGUF (CPU).
/// - Android also accepts a LiteRT-LM `.litertlm` export of the same model,
///   preferred when present for the NNAPI/GPU delegates. None is published
///   yet, so today Android runs the GGUF too.
class ModelManager {
  /// Canonical file name — what Install Packages downloads and what the
  /// Windows release zip ships in `models/`.
  static const brainGgufFileName = 'qwen2.5-coder-1.5b-instruct.gguf';

  /// GGUF discovery order (every platform).
  static const ggufBrainFileNames = [
    brainGgufFileName,
    'qwen_coder_1.5b.Q4_K_M.gguf',
    'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
    'qwen2.5-coder-1.5b-q4.gguf',
  ];

  /// Android LiteRT export names, tried before the GGUF.
  static const liteRtBrainFileNames = [
    'qwen_coder_1.5b.litertlm',
    'qwen2.5-coder-1.5b.litertlm',
    'qwen_coder_1.5b.literlm', // common typo in briefs
  ];

  /// Discovery order for the current platform.
  static List<String> brainFileNamesForPlatform() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const [...liteRtBrainFileNames, ...ggufBrainFileNames];
    }
    return ggufBrainFileNames;
  }

  /// Marks a [ModelInfo.path] that is not a filesystem path but a model
  /// inside the APK's own `assets/models/`, loaded in place by LiteRT-LM.
  static const bundledAssetPrefix = 'bundled:';

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
    final liteRt = path.toLowerCase().endsWith('.litertlm') ||
        path.toLowerCase().endsWith('.literlm');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return liteRt
            ? 'Android (LiteRT-LM · Qwen2.5-Coder 1.5B)'
            : 'Android (llama.cpp · Qwen2.5-Coder 1.5B GGUF)';
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
      canonicalModelInstallPath(brainGgufFileName, ensureDirectory: true);

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
    final android = defaultTargetPlatform == TargetPlatform.android;
    final liteRt = ext == '.litertlm' || ext == '.literlm';
    if (ext != '.gguf' && !(android && liteRt)) {
      throw ModelInstallException(
        android
            ? 'Wrong file type. The tutor model is '
                '$brainGgufFileName (or a .litertlm export of it).'
            : 'Wrong file type. The tutor model is $brainGgufFileName.',
      );
    }

    final size = await source.length();
    if (size < _minSizeBytes) {
      throw const ModelInstallException(
        'That file is too small to be the tutor model — it should be about '
        '1 GB. The download or copy may be incomplete.',
      );
    }

    // A LiteRT export keeps its own name so discovery can tell the two apart.
    final targetPath = liteRt
        ? await canonicalModelInstallPath(
            liteRtBrainFileNames.first,
            ensureDirectory: true,
          )
        : await installTargetPath();
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
          'free storage (about 1.2 GB is needed).',
        );
      }
      rethrow;
    }
    return checkModel();
  }

  /// Where to tell the user to put the model files.
  Future<String> installInstructions() async {
    return 'Transfer the model files to this device, then choose them with '
        'Install from file.\n\n'
        'Tutor (all answers and code):\n'
        '  models/$brainGgufFileName\n\n'
        'Translator: AfriSLM GGUF\n'
        '  models/afrislm-0.8b-q4_k_m.gguf';
  }
}
