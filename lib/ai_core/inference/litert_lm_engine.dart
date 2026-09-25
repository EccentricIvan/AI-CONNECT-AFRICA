import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_scheduler.dart';
import 'inference_engine.dart';
import 'pinned_prompt_cache.dart';
import 'runtime_config.dart';
import 'sanitize_llm_response.dart';

/// A model on Google's LiteRT-LM runtime — the Android runtime for both the
/// brain (Qwen2.5-Coder-1.5B int4) and the AfriSLM translator (int8).
///
/// **Hardware.** Every load asks for [PreferredBackend.npu]. LiteRT-LM then
/// tries NPU (Qualcomm QNN / MediaTek / Tensor vendor dispatch) → GPU
/// (OpenCL/WebGPU) → its own CPU backend, and reports which one it got as
/// [activeBackend]. There is no NNAPI in LiteRT-LM (NNAPI is deprecated in
/// Android 15); the NPU dispatch is its successor. llama.cpp is never a
/// fallback on Android.
///
/// **One engine per role.** Each instance builds its own LiteRT-LM engine
/// with `LiteRtLmEngine().createModel`, not flutter_gemma's single "active
/// model" slot — so the tutor and the translator stay loaded side by side
/// instead of swapping ~1 GB in and out on every local-language turn.
///
/// **Remembering what works.** A GPU/NPU that fails to initialize fails
/// again next launch, and some drivers take a long time to fail. The
/// backend that actually came up is saved per role, and later launches start
/// from it instead of re-trying the accelerator every time. "Reset hardware
/// choice" in Settings clears it ([clearRememberedBackends]).
class LiteRtLmEngineImpl extends InferenceEngine {
  LiteRtLmEngineImpl({
    this.roleLabel = 'Qwen2.5-Coder 1.5B',
    this.roleKey = 'brain',
    this.schedulerLane = EngineLane.reason,
    this.modelType = ModelType.qwen,
    this.contextTokens = 1024,
    this.appendNoThink = false,
    this.isolatedTurns = false,
  });

  /// Shown in Settings / logs.
  final String roleLabel;

  /// Stable id for the remembered backend (`brain`, `translate`).
  final String roleKey;

  /// Lane passed to [EngineScheduler] so brain and translator requests are
  /// serialised exactly as the llama.cpp engines were.
  final String schedulerLane;

  /// flutter_gemma template family. LiteRT-LM applies the bundle's own chat
  /// template on Android; this only matters for its fallbacks.
  final ModelType modelType;

  final int contextTokens;

  /// Qwen3's `/no_think` switch on the user turn — the AfriSLM prompts the
  /// app was tuned with (and the conversion gate) include it.
  final bool appendNoThink;

  /// Translator mode: every call is a fresh conversation with its own
  /// system prompt, never a pinned multi-turn chat. A translation must
  /// never see the previous sentence.
  final bool isolatedTurns;

  InferenceModel? _model;
  InferenceChat? _pinnedChat;
  String? _pinnedSystem;
  String? _loadedPath;
  int _pinnedTurns = 0;
  Future<void> _gate = Future.value();

  PreferredBackend? _activeBackend;
  Duration? _loadTime;
  double? _lastTokensPerSecond;

  /// Recreate the pinned session before KV + THREAD overflow the window.
  static const _maxPinnedTurns = 4;

  static const _prefsPrefix = 'litert_backend_';

  /// The hardware LiteRT-LM actually runs this model on (null until loaded).
  PreferredBackend? get activeBackend => _activeBackend;
  Duration? get loadTime => _loadTime;
  double? get lastTokensPerSecond => _lastTokensPerSecond;

  @override
  bool get isReady => _model != null;

  @override
  String get backendLabel =>
      'LiteRT-LM · $roleLabel · ${backendName(_activeBackend)}';

  String? get loadedPath => _loadedPath;

  static String backendName(PreferredBackend? b) => switch (b) {
        PreferredBackend.npu => 'NPU',
        PreferredBackend.gpu => 'GPU',
        PreferredBackend.cpu => 'CPU',
        null => 'not loaded',
      };

  /// Forget the remembered backends so the next load tries NPU/GPU again.
  static Future<void> clearRememberedBackends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefsPrefix)).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  Future<PreferredBackend> _startingBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('$_prefsPrefix$roleKey');
      for (final b in PreferredBackend.values) {
        if (b.name == saved) return b;
      }
    } catch (_) {}
    return PreferredBackend.npu;
  }

  Future<void> _remember(PreferredBackend backend) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$roleKey', backend.name);
    } catch (_) {}
  }

  @override
  Future<void> loadModel(String modelPath) async {
    await dispose();
    final watch = Stopwatch()..start();
    final start = await _startingBackend();
    final name = modelPath.split(RegExp(r'[\\/]')).last;
    try {
      final model = await const LiteRtLmEngine().createModel(
        InferenceModelSpec(
          name: name,
          modelSource: ModelSource.file(modelPath),
          modelType: modelType,
          fileType: ModelFileType.litertlm,
        ),
        RuntimeConfig(
          maxTokens: contextTokens,
          modelPath: modelPath,
          preferredBackend: start,
        ),
      );
      _model = model;
      _activeBackend = model.activeBackend ?? start;
      _loadedPath = modelPath;
      _loadTime = watch.elapsed;
      await _remember(_activeBackend!);
      debugPrint(
        'LiteRT-LM $roleKey loaded on ${backendName(_activeBackend)} '
        '(asked from ${backendName(start)}) in ${_loadTime!.inMilliseconds} ms: $modelPath',
      );
    } catch (e) {
      throw ModelLoadException('LiteRT-LM failed to load "$modelPath": $e');
    }
  }

  /// Re-bind after a dispose (kept for callers that used the old slot API).
  Future<void> ensureLoaded(String modelPath) async {
    if (_model != null && _loadedPath == modelPath) return;
    await loadModel(modelPath);
  }

  /// Prefill the system contract once so the first student turn skips
  /// re-tokenizing instructions (warm KV / low TTFT).
  Future<void> pinSystemPrompt(String systemPrompt) async {
    if (_model == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }
    if (isolatedTurns) return;
    final sys = PinnedPromptCache.intern(systemPrompt.trim());
    if (_pinnedChat != null && _pinnedSystem == sys) return;
    await _pinnedChat?.close();
    _pinnedChat = await _model!.createChat(
      temperature: kChatTemperature,
      randomSeed: kRandomSeed,
      topK: kTopK,
      topP: kTopP,
      systemInstruction: sys,
      maxOutputTokens: kMaxNewTokens,
      modelType: modelType,
      isThinking: false,
    );
    _pinnedSystem = sys;
    _pinnedTurns = 0;
  }

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    final previous = _gate;
    final done = Completer<void>();
    _gate = done.future;
    try {
      try {
        await previous;
      } catch (_) {}
      return await EngineScheduler.instance.exclusive(
        () => _generateNow(
          prompt: prompt,
          maxTokens: maxTokens,
          temperature: temperature,
          onToken: onToken,
          systemPrompt: systemPrompt,
        ),
        lane: schedulerLane,
      );
    } catch (e) {
      debugPrint('LiteRT-LM $roleKey generate failed: $e');
      const fallback =
          'I hit a brief snag finishing that answer. Please ask again in one short sentence.';
      await emitToken(onToken, fallback);
      return fallback;
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  String _withNoThink(String user) {
    if (!appendNoThink) return user;
    final t = user.trimRight();
    return RegExp(r'/no_think\s*$').hasMatch(t) ? user : '$t\n/no_think';
  }

  Future<String> _generateNow({
    required String prompt,
    required int maxTokens,
    required double temperature,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    if (_model == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    final sys = (systemPrompt == null || systemPrompt.trim().isEmpty)
        ? ''
        : PinnedPromptCache.intern(systemPrompt.trim());
    // Tutor prompts clip tightly; coder briefs (with systemPrompt) must keep
    // the locked feature list — truncating mid-brief + appending "Tutor:"
    // produced broken / empty site and app builds on Android.
    final maxChars = sys.isEmpty ? kTutorMaxPromptChars : kCoderMaxPromptChars;
    final clipped = prompt.length > maxChars
        ? (sys.isEmpty
            ? '${prompt.substring(0, maxChars)}\nTutor:'
            : prompt.substring(0, maxChars))
        : prompt;
    var user = clipped;
    if (sys.isNotEmpty && user.startsWith(sys)) {
      user = user.substring(sys.length).trim();
    }
    user = _withNoThink(user);

    // One-shot: session analysis / website prompts must not append onto the
    // pinned tutor chat, and a translation never sees an earlier sentence.
    if (sys.isEmpty || isolatedTurns) {
      return _oneShot(
        user: user,
        system: sys.isEmpty ? null : sys,
        maxTokens: maxTokens,
        onToken: onToken,
      );
    }

    // Pin the tutor contract once. Later turns only add the user turn, so
    // LiteRT does not re-prefill the system instruction (KV stays warm).
    if (_pinnedChat == null ||
        _pinnedSystem != sys ||
        _pinnedTurns >= _maxPinnedTurns) {
      await _pinnedChat?.close();
      _pinnedChat = await _model!.createChat(
        temperature: kDoSample ? temperature : kChatTemperature,
        randomSeed: kRandomSeed,
        topK: kDoSample ? 40 : kTopK,
        topP: kTopP,
        systemInstruction: sys,
        maxOutputTokens: maxTokens,
        modelType: modelType,
        isThinking: false,
      );
      _pinnedSystem = sys;
      _pinnedTurns = 0;
    }

    final text = await _stream(_pinnedChat!, user, onToken);
    _pinnedTurns++;
    if (text.trim().isEmpty) {
      // The known empty follow-up turn on a reused chat (see memory
      // flutter-gemma-325-blank-followup): drop the pin and answer once more
      // on a fresh conversation rather than show the student nothing.
      await resetSession();
      return _oneShot(user: user, system: sys, maxTokens: maxTokens, onToken: onToken);
    }
    return text;
  }

  Future<String> _stream(InferenceChat chat, String user, TokenCallback? onToken) async {
    await chat.addQueryChunk(Message.text(text: user, isUser: true));
    final cleaner = SanitizedTokenStream();
    final watch = Stopwatch()..start();
    var chunks = 0;
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        final token = response.token;
        if (token.isEmpty) continue;
        chunks++;
        final visible = cleaner.add(token);
        if (visible.isEmpty) continue;
        await emitToken(onToken, visible);
      }
    }
    final tail = cleaner.flush();
    if (tail.isNotEmpty) await emitToken(onToken, tail);
    final secs = watch.elapsedMilliseconds / 1000;
    if (secs > 0 && chunks > 0) _lastTokensPerSecond = chunks / secs;
    return cleaner.text;
  }

  Future<String> _oneShot({
    required String user,
    required String? system,
    required int maxTokens,
    TokenCallback? onToken,
  }) async {
    final chat = await _model!.createChat(
      temperature: isolatedTurns ? kTranslateTemperature : kCoderTemperature,
      randomSeed: kRandomSeed,
      topK: kTopK,
      topP: kTopP,
      systemInstruction: system,
      maxOutputTokens: maxTokens,
      modelType: modelType,
      isThinking: false,
    );
    try {
      return await _stream(chat, user, onToken);
    } finally {
      await chat.close();
    }
  }

  @override
  Future<void> resetSession() async {
    await _pinnedChat?.close();
    _pinnedChat = null;
    _pinnedSystem = null;
    _pinnedTurns = 0;
  }

  @override
  Future<void> dispose() async {
    await resetSession();
    await _model?.close();
    _model = null;
    _loadedPath = null;
    _activeBackend = null;
  }
}
