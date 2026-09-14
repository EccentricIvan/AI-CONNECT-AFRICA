import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai_core/inference/inference_engine.dart';
import '../ai_core/inference/litert_lm_engine.dart';
import '../ai_core/inference/runtime_config.dart';
import '../ai_core/tutor/tutor_contract.dart';
import 'ai_model_manager.dart';
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

  /// Rolling English turns for the next prompt. Not multilingual.
  final List<({String role, String text})> _englishHistory = [];
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
    _englishHistory.add((role: 'user', text: user));
    _englishHistory.add((role: 'assistant', text: assistant));
    const cap = 8;
    if (_englishHistory.length > cap) {
      _englishHistory.removeRange(0, _englishHistory.length - cap);
    }
  }

  void clearHistory() => _englishHistory.clear();

  String historyBlock() {
    if (_englishHistory.isEmpty) return '';
    final buf = StringBuffer('THREAD:\n');
    for (final turn in _englishHistory) {
      buf.writeln('${turn.role == 'user' ? 'Student' : 'Tutor'}: ${turn.text}');
    }
    return buf.toString();
  }

  Future<void> _beforeGenerate(String? systemPrompt) async {
    await AiModelManager.instance.prepareModelForMode(ActiveModelMode.chatBrain);
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
