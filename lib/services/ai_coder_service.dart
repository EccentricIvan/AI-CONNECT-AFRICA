import '../ai_core/inference/inference_engine.dart';
import '../ai_core/inference/runtime_config.dart';
import '../features/app_dev_lab/app_build_coder.dart';
import '../features/site_builder/site_build_coder.dart';
import 'hybrid_model_orchestrator.dart';

/// Site and app builds on the app's one brain, Qwen2.5-Coder-1.5B.
///
/// The same engine answers tutor questions; this service only wraps it with
/// the build prompts. It never loads or unloads a model of its own — the
/// engine belongs to the runtime (`dualModelRuntimeProvider`), so disposing
/// this service must not take the tutor down with it.
///
/// Uses [HybridModelOrchestrator] so a build never overlaps a chat turn or
/// a translation on low-RAM devices.
class AiCoderService {
  AiCoderService({required this.engine});

  final InferenceEngine engine;

  bool get isReady => engine.isReady;

  String get backendLabel => engine.backendLabel;

  /// Kept for callers that check readiness before a build.
  Future<bool> ensureLoaded() async => engine.isReady;

  /// Website Builder one-shot HTML generation.
  Future<String?> generateSiteHtml({
    required SiteBuildIntent intent,
    void Function(String cumulative)? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) return null;
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

  /// Downloadable FastAPI backend scaffold (export-only — never executed
  /// on-device). See [generateAppBackendWithCoder].
  Future<String?> generateAppBackend({
    required AppBuildIntent intent,
    void Function(String cumulative)? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      if (!await ensureLoaded()) return null;
      try {
        return await generateAppBackendWithCoder(
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
        return await engine.generate(
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

  /// Drop session scratch after a build so the next tutor turn starts
  /// clean. Keeps the weights loaded — they are the tutor's too.
  Future<void> releaseAfterJob() async {
    try {
      await engine.resetSession();
    } catch (_) {}
  }

  /// Nothing to release: the engine is owned by the runtime.
  Future<void> dispose() async {}
}
