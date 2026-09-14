import 'package:flutter/foundation.dart';

import '../ai_core/inference/engine_scheduler.dart';
import '../ai_core/inference/inference_engine.dart';
import '../ai_core/inference/llama_cpp_engine.dart';
import '../ai_core/inference/runtime_config.dart';
import '../ai_core/model/model_runtime_policy.dart';
import '../ai_core/model/programming_model_manager.dart';
import '../features/app_dev_lab/app_build_coder.dart';
import '../features/site_builder/site_build_coder.dart';
import 'ai_model_manager.dart';
import 'hybrid_model_orchestrator.dart';

/// Multi-platform Qwen 1.5B Coder for App Dev Lab + Website Builder.
///
/// - **Android** → LiteRT-LM when present; otherwise HF GGUF via llama.cpp.
/// - **Windows / Linux** → llama.cpp GGUF (`qwen2.5-coder-1.5b-instruct.gguf`),
///   **CPU only** (`nGpuLayers: 0`, `threads: 2`).
///
/// Uses [HybridModelOrchestrator] so coder decode never overlaps chat or
/// translation on low-RAM devices. Call [releaseAfterJob] / [dispose] to
/// drop native sessions after builds.
class AiCoderService {
  AiCoderService({
    ProgrammingModelManager? models,
    InferenceEngine? engine,
  })  : _models = models ?? ProgrammingModelManager(),
        _engine = engine;

  final ProgrammingModelManager _models;
  InferenceEngine? _engine;
  String? _loadedPath;

  InferenceEngine? get engine => _engine;

  bool get isReady => _engine?.isReady ?? false;

  String get backendLabel =>
      _engine?.backendLabel ??
      (useLiteRtCoderRuntime
          ? 'LiteRT-LM · Qwen 1.5B Coder (pending)'
          : 'llama.cpp · Qwen 1.5B Coder (pending)');

  /// Resolves the platform model file and binds the matching runtime.
  Future<bool> ensureLoaded() async {
    if (_engine != null && _engine!.isReady) return true;
    final info = await _models.checkModel();
    if (!info.isReady || info.path == null) return false;
    return loadFromPath(info.path!);
  }

  Future<bool> loadFromPath(String path) async {
    if (!isAllowedCoderPath(path)) {
      debugPrint('AiCoderService rejected path: $path');
      return false;
    }
    final lower = path.toLowerCase();
    final wantsLiteRt = useLiteRtCoderRuntime &&
        (lower.endsWith('.litertlm') ||
            lower.endsWith('.literlm') ||
            lower.startsWith('bundled:'));
    if (wantsLiteRt) {
      AiModelManager.instance.registerAppCoderPath(path);
      await AiModelManager.instance.prepareModelForMode(ActiveModelMode.appCoder);
      final eng = AiModelManager.instance.coderEngine;
      if (eng == null || !eng.isReady) return false;
      _engine = eng;
      _loadedPath = path;
      debugPrint('AiCoderService loaded $backendLabel at $path (via swapper)');
      return true;
    }
    await dispose();
    final engine = LlamaCppEngineImpl(
      schedulerLane: EngineLane.program,
      backendLabel: 'llama.cpp · Qwen 1.5B Coder (AVX2 · CPU×2)',
      nGpuLayers: 0,
      threads: 2,
    );
    await engine.loadModel(path);
    _engine = engine;
    _loadedPath = path;
    debugPrint('AiCoderService loaded $backendLabel at $path');
    return true;
  }

  /// Website Builder one-shot HTML generation.
  Future<String?> generateSiteHtml({
    required SiteBuildIntent intent,
    void Function(String cumulative)? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) return null;
      final engine = _engine!;
      try {
        return await generateSiteHtmlWithCoder(
          engine: engine,
          intent: intent,
          onToken: onToken,
        );
      } finally {
        await releaseAfterJob();
      }
    });
  }

  /// App Dev Lab declarative UI schema path (native Flutter preview).
  Future<String?> generateAppUiSchema({
    required AppBuildIntent intent,
    void Function(String cumulative)? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) return null;
      final engine = _engine!;
      try {
        return await generateAppUiSchemaWithCoder(
          engine: engine,
          intent: intent,
          onToken: onToken,
        );
      } finally {
        await releaseAfterJob();
      }
    });
  }

  /// App Dev Lab HTML preview path (chat builder / WebView).
  Future<String?> generateAppHtml({
    required AppBuildIntent intent,
    void Function(String cumulative)? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) return null;
      final engine = _engine!;
      try {
        return await generateAppHtmlWithCoder(
          engine: engine,
          intent: intent,
          onToken: onToken,
        );
      } finally {
        await releaseAfterJob();
      }
    });
  }

  /// App Dev Lab Flutter Dart path.
  Future<String?> generateAppDart({
    required AppBuildIntent intent,
    void Function(String cumulative)? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) return null;
      final engine = _engine!;
      try {
        return await generateAppDartWithCoder(
          engine: engine,
          intent: intent,
          onToken: onToken,
        );
      } finally {
        await releaseAfterJob();
      }
    });
  }

  /// Low-level generate for labs that still pass prompts directly.
  Future<String> generate({
    required String prompt,
    String? systemPrompt,
    int maxTokens = kAppBuildMaxTokens,
    TokenCallback? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) {
        throw StateError('Coder model not installed.');
      }
      try {
        return await _engine!.generate(
          prompt: prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          temperature: kCoderTemperature,
          onToken: onToken,
        );
      } finally {
        await releaseAfterJob();
      }
    });
  }

  /// Drop pinned chat / session scratch after a build (keeps weights mapped).
  /// On Android LiteRT the swapper owns unload — do not dispose here.
  Future<void> releaseAfterJob() async {
    if (useLiteRtCoderRuntime) return;
    try {
      await _engine?.resetSession();
    } catch (e) {
      debugPrint('AiCoderService.releaseAfterJob: $e');
    }
  }

  Future<void> dispose() async {
    if (useLiteRtCoderRuntime) {
      // Owned by [AiModelManager] — only clear local refs.
      _engine = null;
      _loadedPath = null;
      return;
    }
    final engine = _engine;
    _engine = null;
    _loadedPath = null;
    if (engine != null) {
      try {
        await engine.resetSession();
      } catch (_) {}
      await engine.dispose();
    }
  }

  String? get loadedPath => _loadedPath;
}
