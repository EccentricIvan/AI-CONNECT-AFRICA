import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai_core/inference/inference_engine.dart';
import '../ai_core/inference/litert_lm_engine.dart';
import '../ai_core/inference/runtime_config.dart';
import '../ai_core/tutor/conversation_memory.dart';
import '../ai_core/tutor/tutor_contract.dart';
import 'grounded_tutor_prompt.dart';
import 'hybrid_model_orchestrator.dart';

/// Conversational chat/tutor brain.
///
/// - **Android** → LiteRT-LM (`.litertlm`) with NNAPI/GPU + pinned system KV
/// - **Windows** → llama.cpp GGUF with deterministic greedy decode
///
/// System instructions are pinned once ([warmKvCache]) so later turns only
/// append the student message (low TTFT).
class QwenChatService {
  QwenChatService(this._engine, {this.modelPath});

  final InferenceEngine _engine;
  final String? modelPath;

  /// Rolling English conversation memory shared with the tutor prompt path.
  final ConversationMemory englishMemory = ConversationMemory();
  var _kvWarmed = false;

  InferenceEngine get engine => _engine;

  bool get isReady => _engine.isReady;

  String get backendLabel => _engine.backendLabel;

  /// Prefill tutor contract into LiteRT KV (no-op on GGUF beyond intern).
  Future<void> warmKvCache({String? systemPrompt}) async {
    final sys = systemPrompt ?? kTutorContract;
    final litert = _engine;
    if (litert is LiteRtLmEngineImpl) {
      final path = modelPath;
      if (path != null) await litert.ensureLoaded(path);
      await litert.pinSystemPrompt(sys);
    }
    _kvWarmed = true;
  }

  void rememberEnglish({required String user, required String assistant}) {
    englishMemory.remember(student: user, tutor: assistant);
  }

  void clearHistory() => englishMemory.clear();

  String historyBlock() => englishMemory.promptBlock(maxChars: 720);

  Future<void> _beforeGenerate(String? systemPrompt) async {
    if (!_kvWarmed) await warmKvCache(systemPrompt: systemPrompt);
    final litert = _engine;
    if (litert is LiteRtLmEngineImpl && modelPath != null) {
      await litert.ensureLoaded(modelPath!);
      await litert.pinSystemPrompt(systemPrompt ?? kTutorContract);
    }
  }

  Stream<String> streamAnswer({
    required String englishUser,
    String? systemPrompt,
    int maxTokens = kMaxNewTokens,
  }) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        HybridModelOrchestrator.instance.runExclusive(() async {
          try {
            await _beforeGenerate(systemPrompt);
            await _engine.generate(
              prompt: englishUser,
              systemPrompt: systemPrompt ?? kTutorContract,
              maxTokens: maxTokens,
              temperature: kChatTemperature,
              onToken: (token) async {
                if (!controller.isClosed) controller.add(token);
              },
            );
          } catch (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          } finally {
            if (!controller.isClosed) await controller.close();
          }
        });
      },
    );
    return controller.stream;
  }

  Future<String> generateAnswer({
    required String englishUser,
    String? systemPrompt,
    int maxTokens = kMaxNewTokens,
    TokenCallback? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      await _beforeGenerate(systemPrompt);
      return _engine.generate(
        prompt: englishUser,
        systemPrompt: systemPrompt ?? kTutorContract,
        maxTokens: maxTokens,
        temperature: kChatTemperature,
        onToken: onToken,
      );
    });
  }

  // ── Hardgrounded retrieval path ──────────────────────────────────────
  //
  // The student's question is intercepted here, before it reaches the GGUF /
  // LiteRT runtime, and wrapped in the fact-book frame from
  // [grounded_tutor_prompt.dart].
  //
  // Retrieval itself deliberately does NOT happen in this class: it takes an
  // [InferenceEngine] and owns no database handle, and keeping it that way is
  // what lets the whole chat brain be unit-tested with a mock engine and no
  // SQLite at all. The caller runs `OfflineRagService.retrieveContextForQuery`
  // and passes the result in as [retrievedDbChunks]; `GroundedTutorService`
  // does exactly that in one place.

  /// Streams a tutor answer grounded in the teacher's lesson notes.
  ///
  /// [retrievedDbChunks] may be empty — that is the ordinary case for a topic
  /// with no uploaded material, and the frame substitutes the
  /// "use global core textbook definitions" fallback rather than an empty
  /// section.
  Stream<String> streamGroundedAnswer({
    required String studentQuestion,
    required String retrievedDbChunks,
    int maxTokens = kMaxNewTokens,
  }) {
    return streamAnswer(
      englishUser: buildGroundedUserPrompt(
        retrievedDbChunks: retrievedDbChunks,
        studentQuestion: studentQuestion,
      ),
      systemPrompt: kGroundedTutorSystemPrompt,
      maxTokens: maxTokens,
    );
  }

  /// Non-streaming counterpart of [streamGroundedAnswer].
  Future<String> generateGroundedAnswer({
    required String studentQuestion,
    required String retrievedDbChunks,
    int maxTokens = kMaxNewTokens,
    TokenCallback? onToken,
  }) {
    return generateAnswer(
      englishUser: buildGroundedUserPrompt(
        retrievedDbChunks: retrievedDbChunks,
        studentQuestion: studentQuestion,
      ),
      systemPrompt: kGroundedTutorSystemPrompt,
      maxTokens: maxTokens,
      onToken: onToken,
    );
  }

  Future<void> resetSession() async {
    clearHistory();
    _kvWarmed = false;
    await _engine.resetSession();
  }

  Future<void> releaseAfterJob() async {
    // Keep LiteRT system pin warm; only clear English THREAD history on demand.
    debugPrint('QwenChatService turn complete ($backendLabel)');
  }
}

/// Backward-compatible alias used by [ChatInferencePipeline].
class QwenReasoningService {
  QwenReasoningService(InferenceEngine engine, {String? modelPath})
      : _chat = QwenChatService(engine, modelPath: modelPath);

  final QwenChatService _chat;

  InferenceEngine get engine => _chat.engine;

  bool get isReady => _chat.isReady;

  Future<void> warmKvCache({String? systemPrompt}) =>
      _chat.warmKvCache(systemPrompt: systemPrompt);

  void rememberEnglish({required String user, required String assistant}) =>
      _chat.rememberEnglish(user: user, assistant: assistant);

  void clearHistory() => _chat.clearHistory();

  String historyBlock() => _chat.historyBlock();

  Stream<String> streamAnswer({
    required String englishUser,
    String? systemPrompt,
    int maxTokens = kMaxNewTokens,
    double temperature = kChatTemperature,
  }) {
    assert(temperature == kChatTemperature || temperature == 0.0);
    return _chat.streamAnswer(
      englishUser: englishUser,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    );
  }

  Future<void> resetSession() => _chat.resetSession();
}
