import 'dart:async';

import '../ai_core/inference/inference_engine.dart';
import '../ai_core/science/science_text.dart';
import '../ai_core/translate/follow_up_glossary.dart';
import '../ai_core/translate/translation_pipeline.dart';

/// AfriSLM hop: local language ↔ English token streams.
class AfriSlmTranslationService {
  AfriSlmTranslationService(this._pipeline, {this.engine});

  final TranslationPipeline? _pipeline;

  /// Native runtime, when loaded. Null in tests that only stub the pipeline.
  final InferenceEngine? engine;

  bool get isAvailable => _pipeline != null;

  /// Local language → English. Yields tokens as AfriSLM decodes.
  Stream<String> streamToEnglish(String text, String languageCode) async* {
    final trimmed = text.trim();
    if (trimmed.isEmpty || languageCode == 'en') {
      yield text;
      return;
    }
    if (isMathPassThrough(trimmed)) {
      yield repairUnclosedMathDelimiters(trimmed);
      return;
    }
    final glossary = toEnglishFollowUp(trimmed, langCode: languageCode);
    if (glossary != null) {
      yield glossary;
      return;
    }
    if (looksLikeEnglish(trimmed)) {
      yield text;
      return;
    }
    final pipeline = _pipeline;
    if (pipeline == null) {
      yield text;
      return;
    }
    final controller = StreamController<String>();
    final done = pipeline.toEnglishDetailed(
      trimmed,
      languageCode,
      onToken: (token) {
        if (!controller.isClosed) controller.add(token);
      },
    );
    unawaited(done.then((outcome) {
      if (!controller.isClosed) {
        if (controller.hasListener && outcome.translated && outcome.text.isNotEmpty) {
          // Restore math islands after the live tokens if the stream was empty.
        }
        controller.close();
      }
    }).catchError((Object e, StackTrace st) {
      if (!controller.isClosed) controller.addError(e, st);
    }));
    var any = false;
    await for (final chunk in controller.stream) {
      any = true;
      yield chunk;
    }
    final outcome = await done;
    if (!any && outcome.text.isNotEmpty) {
      yield outcome.text;
    }
  }

  /// English → local language. Math / LaTeX clauses skip the GGUF.
  Stream<String> streamToLocal(String english, String languageCode) async* {
    final trimmed = english.trim();
    if (trimmed.isEmpty || languageCode == 'en') {
      yield english;
      return;
    }
    if (isMathPassThrough(trimmed)) {
      yield repairUnclosedMathDelimiters(trimmed);
      return;
    }
    final pipeline = _pipeline;
    if (pipeline == null) {
      yield english;
      return;
    }
    final controller = StreamController<String>();
    final done = pipeline.fromEnglishDetailed(
      trimmed,
      languageCode,
      onToken: (token) {
        if (!controller.isClosed) controller.add(token);
      },
    );
    unawaited(done.then((_) {
      if (!controller.isClosed) controller.close();
    }).catchError((Object e, StackTrace st) {
      if (!controller.isClosed) controller.addError(e, st);
    }));
    var any = false;
    await for (final chunk in controller.stream) {
      any = true;
      yield chunk;
    }
    final outcome = await done;
    if (!any) {
      yield outcome.text;
    }
  }

  Future<TranslationOutcome> toEnglishDetailed(
    String text,
    String languageCode, {
    TokenCallback? onToken,
  }) async {
    if (languageCode == 'en' || text.trim().isEmpty) {
      return TranslationOutcome.passthrough(text);
    }
    if (isMathPassThrough(text)) {
      return TranslationOutcome(
        text: repairUnclosedMathDelimiters(text.trim()),
        translated: true,
      );
    }
    final glossary = toEnglishFollowUp(text, langCode: languageCode);
    if (glossary != null) {
      return TranslationOutcome(text: glossary, translated: true);
    }
    final pipeline = _pipeline;
    if (pipeline == null) {
      return TranslationOutcome(
        text: text,
        translated: false,
        failure: 'translation model unavailable',
      );
    }
    return pipeline.toEnglishDetailed(text, languageCode, onToken: onToken);
  }

  Future<TranslationOutcome> fromEnglishDetailed(
    String text,
    String languageCode, {
    TokenCallback? onToken,
  }) async {
    if (languageCode == 'en' || text.trim().isEmpty) {
      return TranslationOutcome.passthrough(text);
    }
    if (isMathPassThrough(text)) {
      final painted = repairUnclosedMathDelimiters(text.trim());
      await emitToken(onToken, painted);
      return TranslationOutcome(text: painted, translated: true);
    }
    final pipeline = _pipeline;
    if (pipeline == null) {
      return TranslationOutcome(
        text: text,
        translated: false,
        failure: 'translation model unavailable',
      );
    }
    return pipeline.fromEnglishDetailed(text, languageCode, onToken: onToken);
  }
}
