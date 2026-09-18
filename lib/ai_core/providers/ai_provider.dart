import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cloud/cloud_api_settings.dart';
import '../inference/engine_scheduler.dart';
import '../inference/inference_engine.dart';
import '../inference/litert_lm_engine.dart';
import '../inference/llama_cpp_engine.dart';
import '../inference/mock_engine.dart';
import '../inference/openai_compatible_engine.dart';
import '../tutor/tutor_contract.dart';
import '../model/bundled_model_bootstrap.dart';
import '../model/dual_gguf_plan.dart';
import '../model/model_manager.dart';
import '../model/model_runtime_policy.dart';
import '../model/programming_model_manager.dart';
import '../translate/afrislm_model_manager.dart';
import '../translate/drift_translation_store.dart';
import '../translate/follow_up_glossary.dart';
import '../translate/supported_languages.dart';
import '../translate/translation_pipeline.dart';
import '../translate/translation_quality.dart';
import '../tutor/programming_topic.dart';
import '../tutor/tutor_pipeline.dart';
import '../tutor/tutor_response.dart';
import '../tutor/school_math.dart';
import '../tutor/school_math_l10n.dart';
import '../science/science_text.dart';
import '../../curriculum/curriculum_models.dart';
import '../../curriculum/curriculum_provider.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/language_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../safety/emotional_safety.dart';
import '../../services/afrislm_translation_service.dart';
import '../../services/ai_coder_service.dart';
import '../../services/ai_engine_service.dart';
import '../../services/ai_model_manager.dart';
import '../../services/chat_inference_pipeline.dart';
import '../../services/qwen_chat_service.dart';
import '../../services/qwen_reasoning_service.dart';

/// Learn uses curriculum RAG. Wholesome chat (Home `/`) does not.
enum ChatSection { learn, wholesomeChat }

// ── Model status ────────────────────────────────────────────────────────────

final modelManagerProvider = Provider<ModelManager>((ref) => ModelManager());

final translateModelManagerProvider =
    Provider<AfriSlmModelManager>((ref) => AfriSlmModelManager());

/// Streams APK-bundled models into app storage once (Android fat APKs).
/// Slim builds and desktop no-op quickly. Chat/translate providers wait on this.
final bundledModelsBootstrapProvider =
    FutureProvider<BundledModelBootstrapResult>((ref) async {
  if (kIsWeb) {
    return const BundledModelBootstrapResult(
      chatReady: false,
      translateReady: false,
      extractedAnything: false,
    );
  }
  try {
    final bootstrap = BundledModelBootstrap(
      chatManager: ref.watch(modelManagerProvider),
      translateManager: ref.watch(translateModelManagerProvider),
    );
    return await bootstrap.ensureExtracted();
  } catch (e, st) {
    debugPrint('bundledModelsBootstrapProvider failed: $e\n$st');
    return const BundledModelBootstrapResult(
      chatReady: false,
      translateReady: false,
      extractedAnything: false,
      error: 'bootstrap failed',
    );
  }
});

final modelInfoProvider = FutureProvider<ModelInfo>((ref) async {
  if (kIsWeb) {
    return const ModelInfo(status: ModelStatus.notInstalled);
  }
  try {
    final boot = await ref.watch(bundledModelsBootstrapProvider.future);
    final info = await ref.watch(modelManagerProvider).checkModel();
    if (info.isReady) return info;
    if (boot.chatBundledInApk && useLiteRtChatBrain) {
      return const ModelInfo(
        status: ModelStatus.ready,
        path: ModelManager.bundledChatModelPath,
        platform: 'Android (LiteRT-LM · Qwen 0.6B)',
      );
    }
    return info;
  } catch (e, st) {
    debugPrint('modelInfoProvider failed: $e\n$st');
    return const ModelInfo(status: ModelStatus.notInstalled);
  }
});

/// Qwen (brain) + AfriSLM (translator) as two llama.cpp instances.
///
/// [shared] is only true when both roles accidentally point at the same
/// GGUF file — then hops stay sequential to avoid a nested native lock.
/// AfriSLM is never loaded as the tutor brain.
/// Qwen 0.6B (general) + optional Qwen 1.5B Coder + AfriSLM translator.
///
/// AfriSLM is never loaded as the tutor brain. The 1.5B file is loaded on
/// the first programming turn so non-coding students do not pay that RAM.
class DualModelRuntime {
  DualModelRuntime({
    required this.reasoner,
    InferenceEngine? translator,
    this.shared = false,
    this.programmingPath,
    this.afrislmPath,
    InferenceEngine? programming,
  })  : _translator = translator,
        _programming = programming;

  final InferenceEngine reasoner;
  InferenceEngine? _translator;
  final bool shared;
  String? programmingPath;

  /// On-disk AfriSLM path for lazy / retry load after Install Packages.
  String? afrislmPath;
  InferenceEngine? _programming;

  InferenceEngine? get translator => _translator;

  InferenceEngine? get programming => _programming;

  Future<InferenceEngine?>? _translatorLoad;

  /// Load AfriSLM if missing. Never throws — translation stays soft-fail.
  Future<InferenceEngine?> ensureTranslator() async {
    final existing = _translator;
    if (existing != null && existing.isReady) return existing;
    if (shared && identical(existing, reasoner)) return existing;

    final inflight = _translatorLoad;
    if (inflight != null) return inflight;

    final pending = _loadTranslator();
    _translatorLoad = pending;
    try {
      return await pending;
    } finally {
      if (identical(_translatorLoad, pending)) _translatorLoad = null;
    }
  }

  Future<InferenceEngine?> _loadTranslator() async {
    try {
      final info = await AfriSlmModelManager().checkModel();
      if (!info.isReady || info.path == null) {
        debugPrint('TRANSLATION OFF: AfriSLM GGUF not on disk yet.');
        return null;
      }
      afrislmPath = info.path;
      final engine = LlamaCppEngineImpl(
        schedulerLane: EngineLane.translate,
        backendLabel: 'llama.cpp · AfriSLM 0.8B',
      );
      await engine.loadModel(info.path!);
      _translator = engine;
      debugPrint('TRANSLATION ON: AfriSLM at ${info.path}');
      return engine;
    } catch (e, st) {
      debugPrint('TRANSLATION LOAD FAILED: $e\n$st');
      return null;
    }
  }

  Future<InferenceEngine?> ensureProgramming() async {
    if (_programming != null && _programming!.isReady) return _programming;
    var path = programmingPath;
    // On-demand coder fetch may land after DualModelRuntime was built with
    // a null path — rediscover from disk instead of forever falling back
    // to the 0.6B chat brain for labs / Create / Practice.
    if (path == null || path.isEmpty) {
      final info = await ProgrammingModelManager().checkModel();
      final discovered = info.path;
      if (!info.isReady || discovered == null) return null;
      path = discovered;
      programmingPath = discovered;
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
      if (eng == null || !eng.isReady) return null;
      _programming = eng;
      _coderService ??= AiCoderService(engine: eng);
      return eng;
    }

    final coder = AiCoderService();
    final ok = await coder.loadFromPath(path);
    if (!ok || coder.engine == null) return null;
    _programming = coder.engine;
    _coderService = coder;
    return _programming;
  }

  AiCoderService? _coderService;

  AiCoderService? get coderService => _coderService;
}

final dualModelRuntimeProvider = FutureProvider<DualModelRuntime>((ref) async {
  ref.watch(cloudApiReloadTickProvider);

  Future<DualModelRuntime> demo(DemoReason reason) async {
    final mock = MockEngine(demoReason: reason);
    await mock.loadModel('');
    return DualModelRuntime(reasoner: mock);
  }

  try {
    CloudApiConfig cloud;
    try {
      cloud = await ref.watch(cloudApiSettingsProvider.future);
    } catch (e) {
      debugPrint('cloudApiSettingsProvider failed: $e');
      cloud = const CloudApiConfig();
    }
    if (cloud.isConfigured) {
      try {
        final engine = OpenAiCompatibleEngine(cloud);
        await engine.loadModel('');
        ref.onDispose(engine.dispose);
        return DualModelRuntime(reasoner: engine);
      } catch (_) {}
    }

    if (kIsWeb) return demo(DemoReason.web);

    await ref.watch(bundledModelsBootstrapProvider.future);
    final qwenInfo = await ref.watch(modelInfoProvider.future);
    final translateInfo = await ref.watch(translateModelInfoProvider.future);
    final programmingInfo = await ref.watch(programmingModelInfoProvider.future);
    final plan = planDualGgufs(qwenInfo, translateInfo, programmingInfo);
    final programmingPath = plan.programmingPath;

    if (!plan.canTutor ||
        plan.qwenPath == null ||
        !isAllowedChatBrainPath(plan.qwenPath!)) {
      debugPrint(
        useLiteRtChatBrain
            ? 'CHAT BRAIN missing. Place chat-model.litertlm '
                '(LiteRT-LM) in the APK or Install from file.'
            : 'CHAT BRAIN missing. Place qwen_brain_0.6b.Q4_K_M.gguf or '
                'qwen-0.6b-instruct.gguf in models/.',
      );
      return demo(DemoReason.modelNotInstalled);
    }

    final qwenPath = plan.qwenPath!;
    final InferenceEngine reasoner;
    final chatIsLiteRt = useLiteRtChatBrain &&
        (qwenPath.toLowerCase().endsWith('.litertlm') ||
            qwenPath.toLowerCase().endsWith('.literlm') ||
            qwenPath.toLowerCase().startsWith('bundled:'));
    if (chatIsLiteRt) {
      reasoner = LiteRtLmEngineImpl(roleLabel: 'Qwen 0.6B chat');
    } else {
      // Windows/Linux GGUF, or Android HF-fetched GGUF fallback.
      reasoner = LlamaCppEngineImpl(
        schedulerLane: EngineLane.reason,
        backendLabel: 'llama.cpp · Qwen 0.6B chat (AVX2 · CPU×2)',
        nGpuLayers: 0,
        threads: 2,
      );
    }
    await reasoner.loadModel(qwenPath);
    if (reasoner is LiteRtLmEngineImpl) {
      AiModelManager.instance.registerChatBrain(
        engine: reasoner,
        path: qwenPath,
      );
      await reasoner.pinSystemPrompt(kTutorContract);
    }
    if (useLiteRtCoderRuntime &&
        programmingPath != null &&
        (programmingPath.toLowerCase().endsWith('.litertlm') ||
            programmingPath.toLowerCase().endsWith('.literlm') ||
            programmingPath.toLowerCase().startsWith('bundled:'))) {
      AiModelManager.instance.registerAppCoderPath(programmingPath);
    }
    debugPrint(
      'CHAT BRAIN loaded ${chatIsLiteRt ? 'LiteRT-LM (NNAPI/GPU)' : 'llama.cpp GGUF'} '
      'at $qwenPath',
    );

    InferenceEngine? translator;
    var shared = false;
    final afrislmPath = plan.afrislmPath;
    if (plan.canTranslate) {
      if (plan.sameFile) {
        debugPrint(
          'TRANSLATION OFF: AfriSLM path collided with the chat brain. '
          'Install the translation GGUF separately.',
        );
      } else {
        // Soft-fail: never take down the chat brain if AfriSLM OOM / fails
        // after Install Packages on a 4 GB phone.
        try {
          final engine = LlamaCppEngineImpl(
            schedulerLane: EngineLane.translate,
            backendLabel: 'llama.cpp · AfriSLM 0.8B',
          );
          await engine.loadModel(afrislmPath!);
          translator = engine;
          debugPrint('TRANSLATION ON: AfriSLM at $afrislmPath');
        } catch (e, st) {
          debugPrint(
            'TRANSLATION LOAD FAILED (chat stays up; retry on demand): $e\n$st',
          );
          translator = null;
        }
      }
    } else {
      debugPrint('TRANSLATION OFF: no AfriSLM GGUF. English-only tutor.');
    }

    if (programmingPath != null) {
      debugPrint(
        useLiteRtCoderRuntime
            ? 'CODER ready (LiteRT path) at $programmingPath'
            : 'CODER ready (GGUF CPU path) at $programmingPath',
      );
    } else {
      debugPrint(
        'CODER missing. Place qwen2.5-coder-1.5b-instruct.gguf '
        '(or Android LiteRT qwen_coder_1.5b.litertlm) in models/.',
      );
    }

    final runtime = DualModelRuntime(
      reasoner: reasoner,
      translator: translator,
      shared: shared,
      programmingPath: programmingPath,
      afrislmPath: afrislmPath,
    );
    ref.onDispose(() async {
      await reasoner.dispose();
      final t = runtime.translator;
      if (t != null && !identical(t, reasoner)) {
        await t.dispose();
      }
      await runtime.coderService?.dispose();
      if (runtime.coderService == null) {
        await runtime.programming?.dispose();
      }
    });
    return runtime;
  } catch (e, st) {
    debugPrint('dualModelRuntimeProvider failed: $e\n$st');
    return demo(DemoReason.loadFailed);
  }
});

// ── Engine lifecycle ─────────────────────────────────────────────────────────

final engineLoadedProvider = FutureProvider<InferenceEngine>((ref) async {
  return (await ref.watch(dualModelRuntimeProvider.future)).reasoner;
});

final programmingModelManagerProvider =
    Provider<ProgrammingModelManager>((_) => ProgrammingModelManager());

final programmingModelInfoProvider = FutureProvider<ModelInfo>((ref) async {
  if (kIsWeb) {
    return const ModelInfo(status: ModelStatus.notInstalled);
  }
  try {
    await ref.watch(bundledModelsBootstrapProvider.future);
    return ref.watch(programmingModelManagerProvider).checkModel();
  } catch (e, st) {
    debugPrint('programmingModelInfoProvider failed: $e\n$st');
    return const ModelInfo(status: ModelStatus.notInstalled);
  }
});

/// 1.5B Coder when installed, otherwise the 0.6B general brain.
final programmingEngineProvider = FutureProvider<InferenceEngine>((ref) async {
  final runtime = await ref.watch(dualModelRuntimeProvider.future);
  return await runtime.ensureProgramming() ?? runtime.reasoner;
});

/// Hybrid multi-platform coder (LiteRT Android / GGUF CPU Windows).
final aiCoderServiceProvider = FutureProvider<AiCoderService>((ref) async {
  final runtime = await ref.watch(dualModelRuntimeProvider.future);
  await runtime.ensureProgramming();
  final existing = runtime.coderService;
  if (existing != null) return existing;
  final coder = AiCoderService();
  await coder.ensureLoaded();
  ref.onDispose(coder.dispose);
  return coder;
});

/// GGUF / LiteRT chat brain service.
final qwenChatServiceProvider = FutureProvider<QwenChatService>((ref) async {
  final runtime = await ref.watch(dualModelRuntimeProvider.future);
  final info = await ref.watch(modelInfoProvider.future);
  final chat = QwenChatService(runtime.reasoner, modelPath: info.path);
  await chat.warmKvCache();
  return chat;
});

// ── Translation (AfriSLM) ────────────────────────────────────────────────────

final translateModelInfoProvider = FutureProvider<ModelInfo>((ref) async {
  if (kIsWeb) {
    return const ModelInfo(status: ModelStatus.notInstalled);
  }
  try {
    await ref.watch(bundledModelsBootstrapProvider.future);
    return ref.watch(translateModelManagerProvider).checkModel();
  } catch (e, st) {
    debugPrint('translateModelInfoProvider failed: $e\n$st');
    return const ModelInfo(status: ModelStatus.notInstalled);
  }
});

/// Null when translation isn't available (web, no GGUF installed, or
/// llama.cpp failed to load) — translation is always a soft-fail feature,
/// never something that blocks the chat itself.
final translateEngineLoadedProvider = FutureProvider<InferenceEngine?>((ref) async {
  if (kIsWeb) return null;
  final dual = await ref.watch(dualModelRuntimeProvider.future);
  final engine = await dual.ensureTranslator();
  if (engine == null) {
    debugPrint('TRANSLATION OFF: no AfriSLM GGUF loaded.');
  }
  return engine;
});

final translationPipelineProvider = FutureProvider<TranslationPipeline?>((ref) async {
  final engine = await ref.watch(translateEngineLoadedProvider.future);
  if (engine == null) return null;

  // The cache is keyed per model file, so a re-quantized or upgraded GGUF
  // misses rather than serving rows the previous model wrote.
  final modelInfo = await ref.watch(translateModelInfoProvider.future);
  final modelTag = modelInfo.path == null
      ? 'unknown'
      : modelTagFor(
          path: modelInfo.path!,
          sizeBytes: modelInfo.sizeBytes ?? 0,
        );

  return TranslationPipeline(
    engine,
    store: kIsWeb ? null : DriftTranslationStore(ref.watch(dbProvider)),
    modelTag: modelTag,
  );
});

/// Student's learning-language code (`en` if unknown).
///
/// Returning 'en' short-circuits every translation call before the pipeline
/// is even consulted, so a null student (guest, or a profile that has not
/// loaded yet when the first message lands) looks exactly like "translation
/// is broken" from the outside. Log what actually resolved.
///
/// An explicit in-session choice ([languageOverrideProvider]) wins over the
/// stored profile — that is the only way a guest gets a language at all, and
/// it means the model routing agrees with the labels on screen the instant
/// the picker moves, without waiting on the DB write.
///
/// Stays async even though [appLanguageProvider] is synchronous: awaiting the
/// profile is what stops the *first* message of a session being sent
/// untranslated because the student row had not loaded yet.
Future<String> studentLanguageCode(Ref ref) async {
  final override = ref.read(languageOverrideProvider);
  String? persisted;
  try {
    persisted = await ref.read(persistedLanguageProvider.future);
  } catch (e) {
    debugPrint('TRANSLATION: persisted language unread: $e');
  }
  String? studentLanguage;
  try {
    final student = await ref.read(activeStudentProvider.future);
    studentLanguage = student?.language;
    if (student == null) {
      debugPrint('TRANSLATION: no active student row (prefs/override still apply).');
    }
  } catch (e) {
    debugPrint('TRANSLATION OFF: could not read active student: $e');
  }
  final resolved = resolveLearningLanguage(
    override: override,
    persisted: persisted,
    studentLanguage: studentLanguage,
  );
  debugPrint(
    'TRANSLATION lang=$resolved (override=$override prefs=$persisted '
    'student=$studentLanguage)',
  );
  return resolved;
}

/// Best-effort: local-language student text → English for the tutor.
///
/// Pass [langCode] when the caller has already resolved the language for this
/// turn, so one exchange cannot be read in one language and answered in
/// another if the student switches mid-generation.
Future<String> localizeOutgoing(Ref ref, String text, {String? langCode}) async {
  final lang = langCode ?? await studentLanguageCode(ref);
  if (lang == 'en' || text.trim().isEmpty) return text;
  try {
    final pipeline = await ref.read(translationPipelineProvider.future);
    if (pipeline == null) {
      debugPrint('TRANSLATION OFF: no pipeline (in: $lang -> en).');
      return text;
    }
    return await pipeline.toEnglish(text, lang);
  } catch (e) {
    debugPrint('TRANSLATION FAILED (in: $lang -> en): $e');
    return text;
  }
}

/// [localizeIncoming] with the outcome attached, so a caller can tell a real
/// translation from a fallback to English.
///
/// The plain [localizeIncoming] cannot: it returns a String either way, and
/// that ambiguity is exactly how a failed translation used to reach students
/// looking like a working one. Chat uses this; screens that have nowhere to
/// show the distinction keep the simpler wrapper.
Future<TranslationOutcome> localizeIncomingDetailed(
  Ref ref,
  String englishText, {
  TokenCallback? onToken,
  String? langCode,
}) async {
  final lang = langCode ?? await studentLanguageCode(ref);
  if (lang == 'en' || englishText.trim().isEmpty) {
    return TranslationOutcome.passthrough(englishText);
  }
  try {
    final pipeline = await ref.read(translationPipelineProvider.future);
    if (pipeline == null) {
      debugPrint('TRANSLATION OFF: no pipeline (out: en -> $lang).');
      return TranslationOutcome(
        text: englishText,
        translated: false,
        failure: 'translation model unavailable',
      );
    }
    return await pipeline.fromEnglishDetailed(
      englishText,
      lang,
      onToken: onToken,
    );
  } catch (e) {
    debugPrint('TRANSLATION FAILED (out: en -> $lang): $e');
    return TranslationOutcome(
      text: englishText,
      translated: false,
      failure: '$e',
    );
  }
}

/// Best-effort: English tutor text → student's learning language.
Future<String> localizeIncoming(
  Ref ref,
  String englishText, {
  TokenCallback? onToken,
  String? langCode,
}) async {
  final outcome = await localizeIncomingDetailed(
    ref,
    englishText,
    onToken: onToken,
    langCode: langCode,
  );
  return outcome.text;
}

/// Translates a reply and its follow-up prompt.
///
/// This previously returned [followUp] untranslated, so follow-up questions
/// stayed in English even when everything above them was localized.
/// [TranslationPipeline.fromEnglishPair] now translates each part in its own
/// call — AfriSLM was trained on single-text translation, and the labelled
/// two-part prompt this used to send was off-distribution enough that the
/// reply regularly came back unparseable and fell through to English.
Future<(TranslationOutcome, TranslationOutcome)> localizeIncomingPairDetailed(
  Ref ref,
  String reply,
  String followUp, {
  String? langCode,
}) async {
  final lang = langCode ?? await studentLanguageCode(ref);
  if (lang == 'en') {
    return (
      TranslationOutcome.passthrough(reply),
      TranslationOutcome.passthrough(followUp),
    );
  }
  try {
    final pipeline = await ref.read(translationPipelineProvider.future);
    if (pipeline == null) {
      debugPrint('TRANSLATION OFF: no pipeline (pair: en -> $lang).');
      const failure = 'translation model unavailable';
      return (
        TranslationOutcome(text: reply, translated: false, failure: failure),
        TranslationOutcome(text: followUp, translated: false, failure: failure),
      );
    }
    return await pipeline.fromEnglishPairDetailed(reply, followUp, lang);
  } catch (e) {
    debugPrint('TRANSLATION FAILED (pair: en -> $lang): $e');
    return (
      TranslationOutcome(text: reply, translated: false, failure: '$e'),
      TranslationOutcome(text: followUp, translated: false, failure: '$e'),
    );
  }
}

/// Text-only wrapper for [localizeIncomingPairDetailed].
Future<(String, String)> localizeIncomingPair(
  Ref ref,
  String reply,
  String followUp, {
  String? langCode,
}) async {
  final (r, f) =
      await localizeIncomingPairDetailed(ref, reply, followUp, langCode: langCode);
  return (r.text, f.text);
}

/// Warm AfriSLM so the first non-English turn is not blocked on model load.
///
/// If the pipeline resolved to null (file was still downloading, or llama.cpp
/// failed once), rediscover the GGUF and rebuild providers. Never unloads the
/// chat brain.
Future<TranslationPipeline?> ensureTranslationPipeline(Ref ref) async {
  try {
    final existing = await ref.read(translationPipelineProvider.future);
    if (existing != null) return existing;

    final runtime = await ref.read(dualModelRuntimeProvider.future);
    var engine = await runtime.ensureTranslator();
    if (engine == null) {
      ref.invalidate(translateModelInfoProvider);
      final info = await ref.read(translateModelInfoProvider.future);
      if (info.isReady) {
        runtime.afrislmPath = info.path;
        engine = await runtime.ensureTranslator();
      }
    }
    if (engine == null) {
      debugPrint('ensureTranslationPipeline: AfriSLM still unavailable.');
      return null;
    }

    ref.invalidate(translateEngineLoadedProvider);
    ref.invalidate(translationPipelineProvider);
    ref.invalidate(afrislmTranslationServiceProvider);
    ref.invalidate(aiEngineServiceProvider);
    ref.invalidate(chatInferencePipelineProvider);
    return await ref.read(translationPipelineProvider.future);
  } catch (e) {
    debugPrint('ensureTranslationPipeline failed: $e');
    return null;
  }
}

/// Batch-translate path titles. English sessions pass through unchanged.
Future<List<String>> localizeMany(Ref ref, List<String> strings) async {
  if (strings.isEmpty) return strings;
  final lang = await studentLanguageCode(ref);
  if (lang == 'en') return strings;
  final out = <String>[];
  for (final s in strings) {
    out.add(await localizeIncoming(ref, s, langCode: lang));
  }
  return out;
}

/// User-facing AI runtime status (real model vs demo).
class AiStatus {
  const AiStatus({
    required this.isDemo,
    required this.title,
    required this.detail,
    this.backendLabel,
  });

  final bool isDemo;
  final String title;
  final String detail;
  final String? backendLabel;

  factory AiStatus.fromEngine(InferenceEngine engine) {
    if (engine is MockEngine) {
      return AiStatus(
        isDemo: true,
        title: engine.demoReason.title,
        detail: engine.demoReason.detail,
        backendLabel: engine.backendLabel,
      );
    }
    final isCloud = engine.backendLabel.startsWith('Cloud');
    return AiStatus(
      isDemo: false,
      title: isCloud ? 'Cloud AI ready' : 'AI ready',
      detail: isCloud
          ? 'Live answers via ${engine.backendLabel} (needs internet)'
          : 'Using ${engine.backendLabel}',
      backendLabel: engine.backendLabel,
    );
  }
}

final aiStatusProvider = Provider<AsyncValue<AiStatus>>((ref) {
  return ref.watch(engineLoadedProvider).when(
        data: (engine) => AsyncData(AiStatus.fromEngine(engine)),
        loading: () => const AsyncLoading(),
        error: (e, st) => AsyncError(e, st),
      );
});

// ── Tutor pipeline ───────────────────────────────────────────────────────────

final tutorPipelineProvider = FutureProvider<TutorPipeline>((ref) async {
  final engine = await ref.watch(engineLoadedProvider.future);
  final curriculum = ref.watch(curriculumServiceProvider);
  curriculum.loadAll();
  return TutorPipeline(engine: engine, curriculum: curriculum);
});

final qwenReasoningServiceProvider = FutureProvider<QwenReasoningService>((ref) async {
  final runtime = await ref.watch(dualModelRuntimeProvider.future);
  final info = await ref.watch(modelInfoProvider.future);
  final service = QwenReasoningService(
    runtime.reasoner,
    modelPath: info.path,
  );
  await service.warmKvCache();
  return service;
});

final afrislmTranslationServiceProvider =
    FutureProvider<AfriSlmTranslationService?>((ref) async {
  final pipeline = await ref.watch(translationPipelineProvider.future);
  if (pipeline == null) return null;
  final engine = await ref.watch(translateEngineLoadedProvider.future);
  return AfriSlmTranslationService(pipeline, engine: engine);
});

/// Translator isolation facade (no LiteRT/GGUF loaders inside).
final aiEngineServiceProvider = FutureProvider<AiEngineService>((ref) async {
  final translator = await ref.watch(afrislmTranslationServiceProvider.future);
  return AiEngineService(translator);
});

final chatInferencePipelineProvider = FutureProvider<ChatInferencePipeline>((ref) async {
  final runtime = await ref.watch(dualModelRuntimeProvider.future);
  final reasoner = await ref.watch(qwenReasoningServiceProvider.future);
  final tutor = await ref.watch(tutorPipelineProvider.future);
  final translator = await ref.watch(afrislmTranslationServiceProvider.future);
  return ChatInferencePipeline(
    reasoner: reasoner,
    tutor: tutor,
    translator: translator,
    loadProgrammingEngine: runtime.ensureProgramming,
  );
});

// ── Chat state ───────────────────────────────────────────────────────────────

class ChatState {
  const ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.streamingText = '',
    this.streamingMath,
    this.turnTokens = const Stream.empty(),
    this.errorMessage,
  });

  final List<ChatMessage> messages;
  final bool isGenerating;
  final String streamingText;
  final SchoolMathSolution? streamingMath;
  final Stream<String> turnTokens;
  final String? errorMessage;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isGenerating,
    String? streamingText,
    SchoolMathSolution? streamingMath,
    Stream<String>? turnTokens,
    String? errorMessage,
    bool clearError = false,
    bool clearStreamingMath = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      streamingText: streamingText ?? this.streamingText,
      streamingMath:
          clearStreamingMath ? null : (streamingMath ?? this.streamingMath),
      turnTokens: turnTokens ?? this.turnTokens,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    this.stage,
    this.followUp,
    this.isError = false,
    this.translatedLanguage,
    this.translationFailure,
    this.math,
    this.mathCoach = false,
    this.lesson,
  });

  final String text;
  final bool isUser;
  final TutorStage? stage;
  final String? followUp;
  final bool isError;

  /// Set when this message was translated for display — the language code
  /// it was translated into (tutor replies) or the language the student
  /// wrote in and that was translated to English behind the scenes (user
  /// messages). Null means no translation was involved.
  final String? translatedLanguage;

  /// Set when the student is learning in a non-English language but this
  /// reply could not be translated, so what they are reading is English.
  ///
  /// Without this the fallback is invisible: the reply simply arrives in
  /// English and looks like the tutor chose to answer that way. Carrying the
  /// reason lets the UI say "shown in English — translation unavailable"
  /// instead of silently lying by omission.
  final String? translationFailure;

  /// Dart-computed worked solution. Formulas stay in English so translation
  /// cannot scramble the arithmetic.
  final SchoolMathSolution? math;
  final bool mathCoach;

  /// Curriculum lesson matched on this user question (Learn mode).
  final Lesson? lesson;

  ChatMessage copyWith({Lesson? lesson}) {
    return ChatMessage(
      text: text,
      isUser: isUser,
      stage: stage,
      followUp: followUp,
      isError: isError,
      translatedLanguage: translatedLanguage,
      translationFailure: translationFailure,
      math: math,
      mathCoach: mathCoach,
      lesson: lesson ?? this.lesson,
    );
  }
}

class ChatNotifier extends AsyncNotifier<ChatState> {
  ChatSection _section = ChatSection.learn;
  bool _programmingSubject = false;

  @override
  Future<ChatState> build() async {
    return const ChatState();
  }

  static const _safetyEngine = EmotionalSafetyEngine();

  void setSection(ChatSection section) => _section = section;

  void setProgrammingSubject(bool value) => _programmingSubject = value;

  void clearError() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearError: true));
  }

  Future<void> send(String message, {ChatSection? section}) async {
    final current = state.valueOrNull ?? const ChatState();
    if (current.isGenerating) return;
    final useCurriculum =
        (section ?? _section) == ChatSection.learn;

    final thread = <ChatMessage>[
      ...current.messages,
      ChatMessage(text: message, isUser: true),
    ];
    final tokenCtrl = StreamController<String>.broadcast();
    state = AsyncData(current.copyWith(
      messages: List<ChatMessage>.from(thread),
      isGenerating: true,
      streamingText: '',
      turnTokens: tokenCtrl.stream,
      clearError: true,
      clearStreamingMath: true,
    ));

    void pushUi(String cumulative) {
      if (!tokenCtrl.isClosed) tokenCtrl.add(cumulative);
      final cur = state.valueOrNull;
      if (cur == null || !cur.isGenerating) return;
      state = AsyncData(cur.copyWith(streamingText: cumulative));
    }

    final lang = await studentLanguageCode(ref);
    if (lang != 'en') {
      await ensureTranslationPipeline(ref);
    }

    final ChatInferencePipeline cascade;
    try {
      cascade = await ref.read(chatInferencePipelineProvider.future);
      cascade.preferProgramming = _programmingSubject ||
          looksLikeProgramming(message);
    } catch (e) {
      await tokenCtrl.close();
      thread.add(ChatMessage(
        text: _friendlyAiError(e),
        isUser: false,
        isError: true,
      ));
      state = AsyncData(state.requireValue.copyWith(
        messages: List<ChatMessage>.from(thread),
        isGenerating: false,
        streamingText: '',
        errorMessage: _friendlyAiError(e),
      ));
      return;
    }

    String englishForSafety = message;
    if (lang != 'en' &&
        !queryLooksLikeMath(message) &&
        !isMathPassThrough(message)) {
      englishForSafety = toEnglishFollowUp(message, langCode: lang) ??
          await localizeOutgoing(ref, message, langCode: lang);
    }

    final safety = _safetyEngine.check(englishForSafety);
    if (safety.bypassTutor) {
      final support = await localizeIncoming(
        ref,
        safety.supportMessage!,
        langCode: lang,
      );
      pushUi(support);
      await tokenCtrl.close();
      thread.add(ChatMessage(text: support, isUser: false));
      state = AsyncData(state.requireValue.copyWith(
        messages: List<ChatMessage>.from(thread),
        isGenerating: false,
        streamingText: '',
      ));
      return;
    }

    try {
      final hasTranslator =
          cascade.translator != null && cascade.translator!.isAvailable;
      final turn = await cascade.completeTurn(
        userText: message,
        languageCode: lang,
        useCurriculum: useCurriculum,
        safetyNote: safety.tutorNote,
        // Never feed local-language text to Qwen as "English" when AfriSLM
        // is still missing after Install Packages — let the cascade soft-fail.
        pretranslatedEnglish: queryLooksLikeMath(message) ||
                isMathPassThrough(message) ||
                lang == 'en' ||
                !hasTranslator
            ? null
            : englishForSafety,
        onUiToken: pushUi,
      );

      if (turn.response.lesson != null) {
        final lastUserIdx = thread.lastIndexWhere((m) => m.isUser);
        if (lastUserIdx >= 0) {
          thread[lastUserIdx] = thread[lastUserIdx].copyWith(
            lesson: turn.response.lesson,
          );
        }
      }

      var reply = turn.displayText;
      var followUp = turn.response.followUpPrompt;
      var math = turn.response.math;
      var translatedLanguage = turn.translatedLanguage;
      var translationFailure = turn.translationFailure;

      if (math != null) {
        state = AsyncData(state.requireValue.copyWith(streamingMath: math));
        try {
          math = await localizeSchoolMath(
            math,
            langCode: lang,
            translate: (english) async {
              final o = await localizeIncomingDetailed(
                ref,
                english,
                langCode: lang,
              );
              return o.translated ? o.text : english;
            },
            onProgress: (partial) {
              final cur = state.valueOrNull;
              if (cur == null || !cur.isGenerating) return;
              state = AsyncData(cur.copyWith(streamingMath: partial));
            },
          );
          if (lang != 'en') translatedLanguage = lang;
        } catch (e) {
          debugPrint('TRANSLATION FAILED for math steps (en -> $lang): $e');
        }
        if (turn.response.text.trimLeft().startsWith('Step')) {
          reply = '';
        }
      }

      if (followUp.isNotEmpty) {
        followUp = _chromeFollowUp(followUp, lang);
      }

      thread.add(ChatMessage(
        text: reply,
        isUser: false,
        stage: turn.response.stage,
        followUp: followUp,
        translatedLanguage: translatedLanguage,
        translationFailure: translationFailure,
        math: math,
        mathCoach: turn.response.mathCoach,
      ));

      await tokenCtrl.close();
      state = AsyncData(state.requireValue.copyWith(
        messages: List<ChatMessage>.from(thread),
        isGenerating: false,
        streamingText: '',
        clearError: true,
        clearStreamingMath: true,
      ));

      unawaited(_saveSessionSnapshot(
        await ref.read(tutorPipelineProvider.future),
        turn.response,
        thread.length,
      ));
    } catch (e) {
      await tokenCtrl.close();
      final friendly = _friendlyAiError(e);
      thread.add(ChatMessage(text: friendly, isUser: false, isError: true));
      state = AsyncData(state.requireValue.copyWith(
        messages: List<ChatMessage>.from(thread),
        isGenerating: false,
        streamingText: '',
        errorMessage: friendly,
      ));
    }
  }

  Future<void> _saveSessionSnapshot(
    TutorPipeline pipeline,
    TutorResponse response,
    int msgCount,
  ) async {
    try {
      final student = await ref.read(activeStudentProvider.future);
      if (student == null) return;
      final db = ref.read(dbProvider);

      // Truncate — never call the chat model again here (it queued behind
      // the student's next question and made replies feel stuck).
      final summary = response.text.length > 200
          ? '${response.text.substring(0, 200)}…'
          : response.text;

      await db.sessionDao.saveSession(
        studentId: student.id,
        topic: response.topic,
        summary: summary,
        highestStage: response.stage.name,
        messageCount: msgCount,
      );
    } catch (_) {
      // Never crash the chat if DB write fails
    }
  }

  void reset() {
    _programmingSubject = false;
    ref.read(chatInferencePipelineProvider).valueOrNull?.reset();
    ref.read(tutorPipelineProvider).valueOrNull?.reset();
    unawaited(
      ref.read(engineLoadedProvider).valueOrNull?.resetSession() ??
          Future<void>.value(),
    );
    state = const AsyncData(ChatState());
  }
}

String _chromeFollowUp(String followUp, String lang) {
  if (lang == 'en' || followUp.isEmpty) return followUp;
  const keys = [
    'Your turn — try this:',
    'Give it a try and tell me your answer.',
    'Try it, then tell me your answer.',
    'Have another go, or ask me to show the full steps.',
    'Want another problem like this?',
    'Take your time — there are no wrong answers here.',
    'Do you understand so far, or shall I explain it differently?',
    'Can you think of another real-life example like this?',
    'Share what you made or describe your idea.',
    'Great work! Ready to explore the next topic?',
    'Try changing one value in the example and tell me what happens.',
    'In your own words, what does that line of code do?',
    'Paste your attempt — I will check it.',
    'Where would you use this in a real program?',
    'Write a tiny program that uses this idea.',
    'What is one thing you can now do in code that you could not before?',
  ];
  for (final key in keys) {
    if (!hasUiString(lang, key)) continue;
    final localized = uiString(lang, key)!;
    if (followUp == key) return localized;
    if (followUp.startsWith(key)) {
      return '$localized${followUp.substring(key.length)}';
    }
  }
  return followUp;
}

String _friendlyAiError(Object e) {
  final raw = e.toString();
  if (raw.contains('No internet') || raw.contains('SocketException')) {
    return 'No internet for Cloud AI. Connect online, or turn off cloud API in Settings.';
  }
  if (raw.contains('Cloud AI') || raw.contains('api key') || raw.contains('401')) {
    return 'Cloud AI failed. Check your API key and internet in Settings, then try again.';
  }
  if (raw.contains('ModelLoadException') || raw.contains('failed to load')) {
    return 'The AI model failed to load. Open Settings to check the model, then try again.';
  }
  if (raw.contains('SocketException') || raw.contains('Connection')) {
    return 'Couldn’t connect to the local AI. Check the model in Settings, then try again.';
  }
  return 'Couldn’t get an answer just now. Check your AI model in Settings, then try again.';
}

final chatProvider = AsyncNotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

/// Cumulative localized tokens for the in-flight bubble ([StreamBuilder]).
final chatUiTokenStreamProvider = StreamProvider<String>((ref) {
  final tokens = ref.watch(chatProvider).valueOrNull?.turnTokens;
  return tokens ?? const Stream<String>.empty();
});
