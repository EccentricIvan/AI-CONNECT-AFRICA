/// Platform runtime policy for the two-model stack.
///
/// | Role       | Model                     | Android                        | Windows / Linux      |
/// |------------|---------------------------|--------------------------------|----------------------|
/// | Brain      | Qwen2.5-Coder-1.5B        | llama.cpp GGUF, or LiteRT-LM   | llama.cpp GGUF (CPU) |
/// |            | (reasoning, answers, code)| `.litertlm` when one exists    |                      |
/// | Translator | AfriSLM 0.8B              | llama.cpp GGUF                 | llama.cpp GGUF       |
library;

import 'package:flutter/foundation.dart';

/// Android may run the brain on LiteRT-LM (NNAPI/GPU) when a `.litertlm`
/// export is installed; everywhere else it is llama.cpp.
bool get useLiteRtRuntime =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// flutter_gemma / LiteRT only needs initializing where it can run.
bool get shouldInitializeLiteRt => useLiteRtRuntime;

/// True for a LiteRT-LM model (file or APK-bundled asset).
bool isLiteRtModelPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.litertlm') ||
      lower.endsWith('.literlm') ||
      lower.startsWith('bundled:');
}

/// Whether [path] is a brain model this platform can load.
bool isAllowedBrainPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.gguf')) return true;
  return useLiteRtRuntime && isLiteRtModelPath(path);
}
