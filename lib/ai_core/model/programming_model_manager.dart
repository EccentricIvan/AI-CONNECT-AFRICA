import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/model_locations.dart';
import '../model/model_manager.dart' show ModelInfo, ModelStatus;

/// Locates the Qwen 1.5B Coder GGUF used for Python, websites, and apps.
class ProgrammingModelManager {
  static const modelFileName = 'qwen2.5-coder-1.5b-instruct.gguf';

  static const alternateFileNames = [
    'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    'qwen2.5-coder-1.5b-q4.gguf',
    'qwen-1.5b-instruct.gguf',
    'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
  ];

  /// 1.5B Q4 is roughly 0.9–1.2 GB; reject obvious truncations.
  static const _minSizeBytes = 400 * 1024 * 1024;

  Future<List<String>> _candidatePaths() async {
    final names = [modelFileName, ...alternateFileNames];
    final out = <String>[];
    for (final name in names) {
      out.addAll(await modelCandidateFiles(name));
    }
    return out;
  }

  Future<ModelInfo> checkModel() async {
    final candidates = await _candidatePaths();
    debugPrint('PROGRAMMING MODEL candidates:\n  ${candidates.join('\n  ')}');
    ModelInfo? truncated;
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
        );
        continue;
      }
      return ModelInfo(
        status: ModelStatus.ready,
        path: path,
        sizeBytes: size,
      );
    }
    return truncated ?? const ModelInfo(status: ModelStatus.notInstalled);
  }
}
