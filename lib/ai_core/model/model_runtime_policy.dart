/// Platform runtime policy for the hybrid three-model stack.
///
/// | Role        | Android                              | Windows / Linux                 |
/// |-------------|--------------------------------------|---------------------------------|
/// | Chat brain  | LiteRT-LM (`.litertlm`, NNAPI/GPU)   | llama.cpp GGUF (AVX2 CPU)       |
/// | Coder       | LiteRT-LM (`.litertlm`)              | llama.cpp GGUF (CPU×2)          |
/// | Translator  | Isolated via [AiEngineService]       | Isolated via [AiEngineService]  |
library;

import 'package:flutter/foundation.dart';

/// Android chat uses LiteRT for NNAPI / GPU delegates.
bool get useLiteRtChatBrain =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Desktop chat stays on llama.cpp GGUF.
bool get useGgufChatBrain =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.android;

bool get useLiteRtCoderRuntime =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get useGgufCoderRuntime =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.android;

/// FlutterGemma / LiteRT needed whenever Android chat or coder runs.
bool get shouldInitializeLiteRt =>
    useLiteRtChatBrain || useLiteRtCoderRuntime;

bool isAllowedChatBrainPath(String path) {
  final lower = path.toLowerCase();
  if (useLiteRtChatBrain) {
    // Prefer LiteRT on Android; also accept HF-fetched GGUF so one package
    // set works across Play Store installs until a .litertlm is present.
    return lower.endsWith('.litertlm') ||
        lower.endsWith('.literlm') ||
        lower.endsWith('.tflite') ||
        lower.endsWith('.gguf') ||
        lower.startsWith('bundled:');
  }
  return lower.endsWith('.gguf');
}

bool isAllowedCoderPath(String path) {
  final lower = path.toLowerCase();
  if (useLiteRtCoderRuntime) {
    // Prefer LiteRT on Android; accept HF GGUF coder until a .litertlm
    // artifact is published on the package repo.
    return lower.endsWith('.litertlm') ||
        lower.endsWith('.literlm') ||
        lower.endsWith('.gguf') ||
        lower.startsWith('bundled:');
  }
  return lower.endsWith('.gguf');
}

bool get useLiteRtTutorRuntime => useLiteRtChatBrain;

bool get useGgufTutorRuntime => useGgufChatBrain;

bool isAllowedTutorModelPath(String path) => isAllowedChatBrainPath(path);

bool get loadProgrammingGguf => useGgufCoderRuntime;
