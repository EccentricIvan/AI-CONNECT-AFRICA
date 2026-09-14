import '../ai_core/inference/inference_engine.dart';
import '../ai_core/translate/translation_pipeline.dart';
import 'afrislm_translation_service.dart';
import 'hybrid_model_orchestrator.dart';

/// Translator isolation boundary for the hybrid stack.
///
/// **Do not** put LiteRT or GGUF loaders in this file. Translation stays
/// behind [AfriSlmTranslationService] / [TranslationPipeline] (the current
/// production translator). When an NLLB-200 ONNX pack is shipped later, it
/// plugs in here without touching chat or coder services.
///
/// All calls run through [HybridModelOrchestrator] so translator decode
/// never overlaps the chat brain or coder on low-RAM devices.
class AiEngineService {
  AiEngineService(this._translator);

  final AfriSlmTranslationService? _translator;

  bool get isAvailable => _translator?.isAvailable ?? false;

  /// Local → English for the chat brain.
  Future<TranslationOutcome> toEnglishDetailed(
    String text,
    String languageCode, {
    TokenCallback? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      final t = _translator;
      if (t == null) {
        return TranslationOutcome(
          text: text,
          translated: false,
          failure: 'translation model unavailable',
        );
      }
      try {
        return await t.toEnglishDetailed(
          text,
          languageCode,
          onToken: onToken,
        );
      } finally {
        // Pipeline owns native scratch; no LiteRT/GGUF handles here.
      }
    });
  }

  /// English → local for the student UI.
  Future<TranslationOutcome> fromEnglishDetailed(
    String text,
    String languageCode, {
    TokenCallback? onToken,
  }) {
    return HybridModelOrchestrator.instance.runExclusive(() async {
      final t = _translator;
      if (t == null) {
        return TranslationOutcome(
          text: text,
          translated: false,
          failure: 'translation model unavailable',
        );
      }
      try {
        return await t.fromEnglishDetailed(
          text,
          languageCode,
          onToken: onToken,
        );
      } finally {}
    });
  }

  Stream<String> streamToLocal(String english, String languageCode) async* {
    final outcome = await fromEnglishDetailed(english, languageCode);
    if (outcome.text.isNotEmpty) yield outcome.text;
  }

  Stream<String> streamToEnglish(String text, String languageCode) async* {
    final outcome = await toEnglishDetailed(text, languageCode);
    if (outcome.text.isNotEmpty) yield outcome.text;
  }
}
