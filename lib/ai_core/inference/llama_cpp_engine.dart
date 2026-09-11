import 'dart:async';

import 'package:llm_llamacpp/llm_llamacpp.dart' as llama;

import 'engine_scheduler.dart';
import 'inference_engine.dart';
import 'native_ffi_config.dart';
import 'pinned_prompt_cache.dart';
import 'runtime_config.dart';
import 'think_tag_filter.dart';

/// GGUF inference via llama.cpp (`llm_llamacpp`).
///
/// One instance per role: Qwen on [EngineLane.reason], AfriSLM on
/// [EngineLane.translate]. Decode runs in the plugin's persistent isolate.
class LlamaCppEngineImpl extends InferenceEngine {
  LlamaCppEngineImpl({
    this.schedulerLane = EngineLane.reason,
    String backendLabel = 'llama.cpp · GGUF',
  }) : _backendLabel = backendLabel;

  final String schedulerLane;
  final String _backendLabel;

  llama.LlamaCppChatRepository? _repo;
  String? _modelPath;

  String? get loadedModelPath => _modelPath;

  bool _nativeEverWorked = false;
  String? _hardFailure;
  String? _softFailure;
  DateTime? _softFailureUntil;
  int _consecutiveSoftFailures = 0;

  static const _softBackoffBase = Duration(seconds: 30);
  static const _softBackoffMax = Duration(minutes: 5);
  static const _firstTokenTimeout = Duration(minutes: 3);
  static const _betweenTokensTimeout = Duration(seconds: 60);

  @override
  bool get isReady =>
      _repo != null && _modelPath != null && _hardFailure == null;

  @override
  String get backendLabel => _backendLabel;

  String? get failureReason {
    if (_hardFailure != null) return _hardFailure;
    if (_inSoftBackoff) return _softFailure;
    return null;
  }

  bool get isPermanentlyUnavailable => _hardFailure != null;

  bool get _inSoftBackoff {
    final until = _softFailureUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  Future<void> loadModel(String modelPath) async {
    _repo?.dispose();
    _repo = llama.LlamaCppChatRepository.withModelPath(
      modelPath,
      contextSize: kLlamaContextSize,
      batchSize: kLlamaBatchSize,
      nGpuLayers: kLlamaGpuLayers,
    );
    _modelPath = modelPath;
    _nativeEverWorked = false;
    _hardFailure = null;
    _softFailure = null;
    _softFailureUntil = null;
    _consecutiveSoftFailures = 0;
  }

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    final repo = _repo;
    final modelPath = _modelPath;
    if (repo == null || modelPath == null) {
      throw StateError('GGUF model not loaded.');
    }
    final hard = _hardFailure;
    if (hard != null) throw StateError(hard);
    if (_inSoftBackoff) {
      throw StateError(
        '${_softFailure ?? 'AfriSLM stalled recently.'} Retrying after a '
        'short backoff.',
      );
    }

    final greedyTemp = kDoSample ? temperature : kTutorTemperature;
    return EngineScheduler.instance.exclusive(
      () => _generateLocked(
          repo: repo,
          modelPath: modelPath,
          prompt: prompt,
          maxTokens: maxTokens,
          temperature: greedyTemp,
          onToken: onToken,
          systemPrompt: systemPrompt,
        ),
      lane: schedulerLane,
    );
  }

  Future<String> _generateLocked({
    required llama.LlamaCppChatRepository repo,
    required String modelPath,
    required String prompt,
    required int maxTokens,
    required double temperature,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    final sys = (systemPrompt == null || systemPrompt.trim().isEmpty)
        ? null
        : PinnedPromptCache.intern(systemPrompt.trim());

    final stream = repo.streamChatWithGenerationOptions(
      modelPath,
      messages: [
        if (sys != null)
          llama.LLMMessage(role: llama.LLMRole.system, content: sys),
        llama.LLMMessage(role: llama.LLMRole.user, content: prompt),
      ],
      think: false,
      generationOptions: llama.GenerationOptions(
        maxTokens: maxTokens,
        temperature: temperature,
        topP: kTopP,
        topK: kTopK,
        seed: kRandomSeed,
      ),
    );

    final filter = ThinkTagFilter();
    final buffer = StringBuffer();
    final done = Completer<void>();
    StreamSubscription<llama.LLMChunk>? sub;
    Timer? watchdog;

    void fail(String message) {
      if (done.isCompleted) return;
      if (!_nativeEverWorked) {
        _hardFailure = message;
      } else {
        _consecutiveSoftFailures++;
        final backoff =
            _softBackoffBase * (1 << (_consecutiveSoftFailures - 1));
        _softFailure = message;
        _softFailureUntil = DateTime.now()
            .add(backoff > _softBackoffMax ? _softBackoffMax : backoff);
      }
      watchdog?.cancel();
      unawaited(sub?.cancel());
      done.completeError(StateError(message));
    }

    void arm(Duration limit) {
      watchdog?.cancel();
      watchdog = Timer(limit, () {
        fail(
          _nativeEverWorked
              ? 'AfriSLM stalled for ${limit.inSeconds}s with no new output.'
              : 'AfriSLM produced no output within ${limit.inSeconds}s. '
                  'The llama.cpp native library most likely failed to load; '
                  'on Windows that happens when the Vulkan runtime is '
                  'missing, because ggml.dll imports ggml-vulkan.dll at '
                  'load time.',
        );
      });
    }

    arm(_firstTokenTimeout);
    sub = stream.listen(
      (chunk) {
        final text = chunk.message?.content;
        if (text == null || text.isEmpty) return;
        _nativeEverWorked = true;
        _consecutiveSoftFailures = 0;
        _softFailure = null;
        _softFailureUntil = null;
        final visible = filter.add(text);
        if (visible.isEmpty) {
          arm(_betweenTokensTimeout);
          return;
        }
        buffer.write(visible);
        unawaited(emitToken(onToken, visible));
        arm(_betweenTokensTimeout);
      },
      onError: (Object e, StackTrace st) {
        if (done.isCompleted) return;
        watchdog?.cancel();
        done.completeError(e, st);
      },
      onDone: () {
        if (done.isCompleted) return;
        watchdog?.cancel();
        done.complete();
      },
      cancelOnError: true,
    );

    try {
      await done.future;
    } finally {
      watchdog?.cancel();
      await sub.cancel();
    }

    final tail = filter.flush();
    if (tail.isNotEmpty) {
      buffer.write(tail);
      await emitToken(onToken, tail);
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw StateError('AfriSLM returned an empty response.');
    }
    return result;
  }

  @override
  Future<void> dispose() async {
    _repo?.dispose();
    _repo = null;
    _modelPath = null;
    _hardFailure = null;
    _softFailure = null;
    _softFailureUntil = null;
    _consecutiveSoftFailures = 0;
    _nativeEverWorked = false;
  }
}
