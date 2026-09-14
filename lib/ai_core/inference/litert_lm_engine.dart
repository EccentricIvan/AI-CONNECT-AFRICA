import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../model/model_manager.dart';
import 'inference_engine.dart';
import 'pinned_prompt_cache.dart';
import 'runtime_config.dart';
import 'sanitize_llm_response.dart';

/// Chat engine for every desktop/mobile platform — Google LiteRT-LM runtime
/// via flutter_gemma_litertlm, registered in main.dart. Runs Qwen3-0.6B
/// entirely on-device from a single .litertlm model file.
///
/// On Windows/Linux this always requests the CPU backend. On-device testing
/// on a real (weak/older) Windows GPU found the native WebGPU backend
/// doesn't fail fast on unsupported hardware — it silently falls back to a
/// software adapter and hangs for ~11 minutes in `WaitForCompletion` before
/// erroring. That's inside the compiled Google binary; a Dart-side
/// `Future.timeout()` around the call does not help — it only stops *this*
/// isolate from waiting, it does not interrupt the blocking native call
/// underneath, which keeps running for its own full internal timeout
/// regardless (confirmed: the native call still took ~11 minutes even with
/// a 45s Dart timeout wrapped around it). Since there's no way to safely
/// detect a bad GPU ahead of time without risking that same hang during the
/// probe, desktop skips the GPU path entirely. Android keeps the platform
/// default (GPU/NPU delegate when available), since it's the primary target
/// and this machine's finding doesn't generalize to it.
class LiteRtLmEngineImpl extends InferenceEngine {
  LiteRtLmEngineImpl({this.roleLabel = 'Qwen3-0.6B'});

  /// Distinguishes chat vs coder in logs when both share FlutterGemma.
  final String roleLabel;

  InferenceModel? _model;
  InferenceChat? _pinnedChat;
  String? _pinnedSystem;
  String? _loadedPath;
  int _pinnedTurns = 0;
  Future<void> _gate = Future.value();

  /// Recreate the pinned session before KV + THREAD overflow the 1024 window.
  static const _maxPinnedTurns = 4;

  static bool get _cpuOnly =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  bool get isReady => _model != null;

  @override
  String get backendLabel =>
      'LiteRT-LM · $roleLabel${_cpuOnly ? ' (CPU)' : ' (NNAPI/GPU)'}';

  String? get loadedPath => _loadedPath;

  @override
  Future<void> loadModel(String modelPath) async {
    // A "bundled:" path means the model is still inside the APK's own
    // assets/models/ folder. flutter_gemma's BundledSourceHandler records
    // metadata only ("no copying required — uses native path directly"), so
    // LiteRT-LM mmaps the asset in place and the fat APK never grows a
    // second copy of the same ~600 MB in app storage. This relies on the
    // `noCompress` rule for .litertlm in build.gradle.kts — a deflated
    // asset has no mappable file descriptor.
    final bundledName = modelPath.startsWith(ModelManager.bundledAssetPrefix)
        ? modelPath.substring(ModelManager.bundledAssetPrefix.length)
        : null;

    final installName = bundledName ??
        modelPath.split(RegExp(r'[\\/]')).last;

    Future<void> install() {
      final builder = FlutterGemma.installModel(
        modelType: ModelType.qwen3,
        fileType: ModelFileType.litertlm,
      );
      return (bundledName == null
              ? builder.fromFile(modelPath)
              : builder.fromBundled(bundledName))
          .install();
    }

    try {
      final installed = await FlutterGemma.isModelInstalled(installName);
      if (!installed) {
        await install();
      }
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
          preferredBackend: _cpuOnly ? PreferredBackend.cpu : null,
        );
      } catch (_) {
        await install();
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
          preferredBackend: _cpuOnly ? PreferredBackend.cpu : null,
        );
      }
      _loadedPath = modelPath;
      // Drop any prior pin — weights changed / active model swapped.
      await resetSession();
    } catch (e) {
      throw ModelLoadException('LiteRT-LM failed to load "$modelPath": $e');
    }
  }

  /// Re-bind if FlutterGemma's single active slot was stolen by the coder.
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
      modelType: ModelType.qwen3,
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
      return await _generateNow(
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        onToken: onToken,
        systemPrompt: systemPrompt,
      );
    } finally {
      if (!done.isCompleted) done.complete();
    }
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
    final maxChars =
        sys.isEmpty ? kTutorMaxPromptChars : kCoderMaxPromptChars;
    final clipped = prompt.length > maxChars
        ? (sys.isEmpty
            ? '${prompt.substring(0, maxChars)}\nTutor:'
            : prompt.substring(0, maxChars))
        : prompt;
    var user = clipped;
    if (sys.isNotEmpty && user.startsWith(sys)) {
      user = user.substring(sys.length).trim();
    }

    // Session analysis / website prompts must not append onto the pinned
    // tutor chat — that would pollute the KV the student is learning from.
    if (sys.isEmpty) {
      return _oneShot(user: user, maxTokens: maxTokens, onToken: onToken);
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
        modelType: ModelType.qwen3,
        isThinking: false,
      );
      _pinnedSystem = sys;
      _pinnedTurns = 0;
    }

    await _pinnedChat!.addQueryChunk(Message.text(text: user, isUser: true));

    final cleaner = SanitizedTokenStream();
    await for (final response in _pinnedChat!.generateChatResponseAsync()) {
      if (response is TextResponse) {
        final token = response.token;
        if (token.isNotEmpty) {
          final visible = cleaner.add(token);
          if (visible.isEmpty) continue;
          await emitToken(onToken, visible);
        }
      }
    }
    final tail = cleaner.flush();
    if (tail.isNotEmpty) await emitToken(onToken, tail);
    _pinnedTurns++;
    return cleaner.text;
  }

  Future<String> _oneShot({
    required String user,
    required int maxTokens,
    TokenCallback? onToken,
  }) async {
    final chat = await _model!.createChat(
      temperature: kCoderTemperature,
      randomSeed: kRandomSeed,
      topK: kTopK,
      topP: kTopP,
      maxOutputTokens: maxTokens,
      modelType: ModelType.qwen3,
      isThinking: false,
    );
    try {
      await chat.addQueryChunk(Message.text(text: user, isUser: true));
      final cleaner = SanitizedTokenStream();
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          final token = response.token;
          if (token.isNotEmpty) {
            final visible = cleaner.add(token);
            if (visible.isEmpty) continue;
            await emitToken(onToken, visible);
          }
        }
      }
      final tail = cleaner.flush();
      if (tail.isNotEmpty) await emitToken(onToken, tail);
      return cleaner.text;
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
    _model?.close();
    _model = null;
    _loadedPath = null;
  }
}
