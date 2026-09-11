import 'dart:async';

import 'engine_scheduler.dart';
import 'litert_lm_engine.dart';
import 'llama_cpp_engine.dart';

/// Token-by-token streaming callback.
///
/// May return a [Future] so the brain loop can await outbound AfriSLM
/// after a clause flush when both hops share one GGUF.
typedef TokenCallback = FutureOr<void> Function(String token);

/// Awaits [onToken] when it returns a [Future].
Future<void> emitToken(TokenCallback? onToken, String token) async {
  if (onToken == null) return;
  await Future.sync(() => onToken(token));
}

/// Unified inference interface.
/// - Reason (Qwen 0.6B GGUF)         → [LlamaCppEngineImpl] (`EngineLane.reason`)
/// - Program (Qwen 1.5B Coder GGUF)  → [LlamaCppEngineImpl] (`EngineLane.program`)
/// - Translate (AfriSLM GGUF)        → [LlamaCppEngineImpl] (`EngineLane.translate`)
/// - Fallback (Qwen3-0.6B `.litertlm`) → [LiteRtLmEngineImpl]
/// - Dev/Test                        → [MockEngine]
abstract class InferenceEngine {
  bool get isReady;
  String get backendLabel;

  /// True when answers are canned demos, not a real local model.
  bool get isDemo => false;

  /// Load the model file from [modelPath].
  Future<void> loadModel(String modelPath);

  /// Generate a response, streaming tokens via [onToken].
  ///
  /// [systemPrompt] is interned and sent as a system turn.
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  });

  /// Token stream over [generate]. Errors close the stream with that error.
  Stream<String> streamGenerate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    String? systemPrompt,
  }) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        generate(
          prompt: prompt,
          maxTokens: maxTokens,
          temperature: temperature,
          systemPrompt: systemPrompt,
          onToken: (token) {
            if (!controller.isClosed) controller.add(token);
          },
        ).then((_) {
          if (!controller.isClosed) controller.close();
        }).catchError((Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
        });
      },
    );
    return controller.stream;
  }

  /// Drop a pinned chat session (tutor "New session").
  Future<void> resetSession() async {}

  /// Release native resources.
  Future<void> dispose();
}

class ModelLoadException implements Exception {
  ModelLoadException(this.message);
  final String message;
  @override
  String toString() => 'ModelLoadException: $message';
}

/// Reasoning engine — LiteRT-LM Qwen3-0.6B (`.litertlm`).
InferenceEngine createPlatformEngine() {
  return LiteRtLmEngineImpl();
}
