import 'dart:async';

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
/// - Brain (every platform): Qwen2.5-Coder-1.5B GGUF → [LlamaCppEngineImpl],
///   or a `.litertlm` export on Android → [LiteRtLmEngineImpl]. It does all
///   reasoning and answering, tutoring and code alike.
/// - Translate: AfriSLM via isolated [AiEngineService] / llama.cpp
/// - Dev/Test → [MockEngine]
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

/// LiteRT-LM engine for a `.litertlm` brain export.
InferenceEngine createPlatformEngine() {
  return LiteRtLmEngineImpl();
}
