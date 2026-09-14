import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/model_locations.dart';
import '../model/model_manager.dart' show ModelInfo, ModelStatus;
import '../model/model_runtime_policy.dart';

/// Locates the Qwen 1.5B Coder for App Dev Lab / Website Builder.
///
/// - Android → LiteRT `qwen_coder_1.5b.litertlm` (and aliases)
/// - Windows → llama.cpp `qwen_coder_1.5b.Q4_K_M.gguf` (and aliases)
class ProgrammingModelManager {
  static const litertCoderFileName = 'qwen_coder_1.5b.litertlm';
  static const ggufCoderFileName = 'qwen_coder_1.5b.Q4_K_M.gguf';

  /// Legacy Windows release name.
  static const modelFileName = 'qwen2.5-coder-1.5b-instruct.gguf';

  static const litertAlternateFileNames = [
    litertCoderFileName,
    'qwen_coder_1.5b.literlm', // common typo in briefs
    'qwen2.5-coder-1.5b.litertlm',
  ];

  static const alternateFileNames = [
    ggufCoderFileName,
    modelFileName,
    'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    'qwen2.5-coder-1.5b-q4.gguf',
    'qwen-1.5b-instruct.gguf',
    'Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
  ];

  static const _minSizeBytes = 400 * 1024 * 1024;

  Future<List<String>> _candidatePaths() async {
    final names = useLiteRtCoderRuntime
        ? litertAlternateFileNames
        : alternateFileNames;
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
      if (!isAllowedCoderPath(path)) continue;
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
