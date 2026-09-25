/// Which runtime each platform uses — one runtime per platform, no mixing.
///
/// | Platform        | Runtime   | Model files                         | Hardware                     |
/// |-----------------|-----------|-------------------------------------|------------------------------|
/// | Android         | LiteRT-LM | `.litertlm` (brain + translator)    | NPU → GPU → LiteRT CPU       |
/// | Windows / Linux | llama.cpp | `.gguf` (brain + translator)        | CPU (see runtime_config.dart)|
///
/// Android never loads llama.cpp (its native libraries are not even packed
/// into the APK — see android/app/build.gradle.kts), and desktop never
/// initializes LiteRT. A model file in the other platform's format is not
/// "installed" as far as that platform is concerned.
library;

import 'package:flutter/foundation.dart';

/// Android: both models on LiteRT-LM.
bool get androidUsesLiteRt =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Windows / Linux / macOS: both models on llama.cpp.
bool get desktopUsesLlamaCpp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Kept for older call sites: LiteRT is used exactly where Android is.
bool get useLiteRtRuntime => androidUsesLiteRt;

/// flutter_gemma / LiteRT only needs initializing where it runs.
bool get shouldInitializeLiteRt => androidUsesLiteRt;

/// The model file extension this platform runs.
String get platformModelExtension => androidUsesLiteRt ? '.litertlm' : '.gguf';

/// True for a LiteRT-LM model file.
bool isLiteRtModelPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.litertlm') || lower.endsWith('.literlm');
}

/// True for a llama.cpp model file.
bool isGgufModelPath(String path) => path.toLowerCase().endsWith('.gguf');

/// Whether this platform's runtime can load [path] — Android `.litertlm`
/// only, desktop `.gguf` only.
bool isAllowedModelPath(String path) =>
    androidUsesLiteRt ? isLiteRtModelPath(path) : isGgufModelPath(path);

/// Same rule for the brain (kept as its own name for existing callers).
bool isAllowedBrainPath(String path) => isAllowedModelPath(path);
