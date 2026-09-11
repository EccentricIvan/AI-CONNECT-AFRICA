import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../inference/inference_engine.dart';
import '../inference/pinned_prompt_cache.dart';
import '../inference/runtime_config.dart';
import '../science/science_text.dart';
import 'chat_languages.dart';
import 'translation_quality.dart';

/// Prompt-based translator (AfriSLM GGUF). Mocks stay on [TranslationPipeline]
/// for unit tests.
abstract class SequenceTranslator {
  Future<String> translatePair({
    required String text,
    required String sourceFlores,
    required String targetFlores,
    int maxNewTokens = 256,
  });
}

/// True when [text] is very likely already English (Latin + common words).
/// Used to skip a slow AfriSLM round-trip when the student typed English.
///
/// Deliberately hard to trigger. A false positive here is not a slow path,
/// it is a *wrong* one: the student's message goes to the tutor untranslated
/// and comes back as nonsense, which reads exactly like the model
/// hallucinating. The earlier version needed only two hits from a list that
/// included ' a ' and ' i ' — both standalone words in Yoruba and Hausa — so
/// ordinary sentences in those languages were being passed through as
/// "English". Single-letter markers are gone and the threshold is three.
bool looksLikeEnglish(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (RegExp(r'[ሀ-፿]').hasMatch(t)) return false; // Ge'ez (Amharic)
  final padded = ' ${t.toLowerCase()} ';
  const markers = [
    ' the ', ' is ', ' are ', ' what ', ' how ', ' why ', ' you ',
    " i'm ", ' to ', ' in ', ' of ', ' and ', ' for ',
    ' my ', ' can ', ' do ', ' this ', ' that ', ' please ', ' explain ',
  ];
  var hits = 0;
  for (final m in markers) {
    if (padded.contains(m)) hits++;
  }
  return hits >= 3;
}

/// Persistent store behind the translation cache.
///
/// An interface rather than a direct drift dependency so the pipeline stays
/// unit-testable without a database, and so a cache failure is structurally
/// incapable of breaking a translation: [TranslationPipeline] treats every
/// call here as best-effort.
abstract class TranslationStore {
  Future<String?> lookup(String cacheKey, String expectedSource);

  Future<void> save({
    required String cacheKey,
    required String langCode,
    required String direction,
    required String modelTag,
    required String sourceText,
    required String translatedText,
  });
}

/// What a translation attempt actually produced.
///
/// [text] is always safe to display. [translated] says whether it is a real
/// translation or the untranslated original — callers must not assume the
/// former, because assuming it is what let silent English fallbacks look
/// like working translations for so long.
class TranslationOutcome {
  const TranslationOutcome({
    required this.text,
    required this.translated,
    this.fromCache = false,
    this.failure,
  });

  const TranslationOutcome.passthrough(this.text)
      : translated = false,
        fromCache = false,
        failure = null;

  final String text;
  final bool translated;
  final bool fromCache;

  /// Why translation did not happen, for logs and for the "translation
  /// unavailable" state in the UI. Null when [translated] is true.
  final String? failure;
}

/// Wraps AfriSLM with cached, validated translation prompts.
/// ChatNotifier streams Qwen English through this layer; math islands skip it.
class TranslationPipeline {
  TranslationPipeline(
    this._engine, {
    TranslationStore? store,
    String modelTag = 'unknown',
  })  : _store = store,
        _modelTag = modelTag;

  final InferenceEngine _engine;
  final TranslationStore? _store;

  /// Session cache that does not depend on Drift. The documents directory
  /// is missing in some desktop/dev launches, which makes every store
  /// lookup fail and forced a full GGUF reload on every identical string.
  static const _memoryCap = 256;
  final Map<String, String> _memory = {};

  /// Identifies the GGUF that produces these translations. Part of every
  /// cache key so a re-quantized or upgraded model never serves rows the
  /// previous file wrote.
  final String _modelTag;

  /// The prompt format TranslatePsy-AfriSLM was actually trained on, taken
  /// from its model card.
  ///
  /// This matters more than anything else in this file. The model is 0.8B
  /// and quantised to 4-bit; it holds its shape only near the distribution
  /// it was tuned on. We previously sent a bare "Translate to Swahili.
  /// Output the translation only." with no system turn at all, which is off
  /// that distribution and is where invented text and commentary creep in.
  String _systemPrompt(String from, String to) {
    final base =
        'You are a professional $from to $to translator. Your goal is to '
        'accurately convey the meaning and nuances of the original $from text '
        'while adhering to $to grammar, vocabulary, and cultural '
        'sensitivities. Produce only the $to translation, without any '
        'additional explanations or commentary.';
    final style = chatTranslateStyle(to);
    if (style == null) return PinnedPromptCache.intern(base);
    return PinnedPromptCache.intern('$base $style');
  }

  String _userPrompt(String from, String to, String text) =>
      'Please translate the following $from text into $to: $text.\n\n'
      'Translation:';

  /// Stable key for one (model, direction, language, text) tuple.
  ///
  /// The source text is normalized for whitespace only — case and
  /// punctuation are meaningful to a translator, so "how?" and "How"
  /// deliberately do not share a cache row.
  String _cacheKey({
    required String direction,
    required String langCode,
    required String text,
  }) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final raw = '$_modelTag|$direction|$langCode|$normalized';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// One validated translation, with one retry.
  ///
  /// The retry is not a plain repeat: the first pass runs the model's own
  /// trained prompt, and the retry applies [strictEnglishCheck] = false so
  /// the weakest heuristic cannot reject twice and cost the student a
  /// translation that was probably fine.
  Future<TranslationOutcome> _translate({
    required String text,
    required String fromName,
    required String toName,
    required String toCode,
    required String direction,
    required String cacheLangCode,
    TokenCallback? onToken,
  }) async {
    final source = text.trim();
    if (source.isEmpty) return TranslationOutcome.passthrough(text);
    // Cache identity matches [_cacheKey]: collapse whitespace so "How  are"
    // and "How are" share a row. The model still sees [source] as typed.
    final cacheSource = source.replaceAll(RegExp(r'\s+'), ' ');

    final key = _cacheKey(
      direction: direction,
      langCode: cacheLangCode,
      text: cacheSource,
    );

    // ── Cache ────────────────────────────────────────────────────────────
    final cached = await _cacheLookup(key, cacheSource);
    if (cached != null) {
      // Replay through onToken so a streaming caller still renders, and
      // does so instantly instead of over several seconds.
      await emitToken(onToken, cached);
      return TranslationOutcome(
        text: cached,
        translated: true,
        fromCache: true,
      );
    }

    // ── Model, with one validated retry ──────────────────────────────────
    TranslationRejection? lastRejection;
    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      final strict = attempt == 0;
      try {
        final String raw;
        raw = await _engine.generate(
          prompt: _userPrompt(fromName, toName, source),
          systemPrompt: _systemPrompt(fromName, toName),
          maxTokens: _tokenBudget(source),
          temperature: kTranslateTemperature,
          onToken: strict ? onToken : null,
        );
        final candidate = cleanTranslationOutput(raw);
        if (candidate.isEmpty) {
          debugPrint(
            'TRANSLATION RAW emptied ($direction $cacheLangCode): '
            '[${raw.replaceAll('\n', r'\n')}]',
          );
        }
        final rejection = judgeTranslation(
          source: source,
          candidate: candidate,
          toCode: toCode,
          strictEnglishCheck: strict,
        );
        if (rejection == null) {
          await _cacheSave(
            key: key,
            langCode: cacheLangCode,
            direction: direction,
            source: cacheSource,
            translated: candidate,
          );
          return TranslationOutcome(text: candidate, translated: true);
        }
        lastRejection = rejection;
        debugPrint(
          'TRANSLATION REJECTED (attempt ${attempt + 1}, $direction '
          '$cacheLangCode): ${rejection.label}',
        );
      } catch (e) {
        lastError = e;
        debugPrint(
          'TRANSLATION ERROR (attempt ${attempt + 1}, $direction '
          '$cacheLangCode): $e',
        );
      }
    }

    final reason = lastRejection?.label ??
        (lastError != null ? 'engine error: $lastError' : 'unknown');
    return TranslationOutcome(text: text, translated: false, failure: reason);
  }

  Future<String?> _cacheLookup(String key, String source) async {
    final mem = _memory[key];
    if (mem != null) return mem;
    final store = _store;
    if (store == null) return null;
    try {
      final hit = await store.lookup(key, source);
      if (hit != null) _memoryPut(key, hit);
      return hit;
    } catch (e) {
      debugPrint('TRANSLATION CACHE lookup failed (ignored): $e');
      return null;
    }
  }

  Future<void> _cacheSave({
    required String key,
    required String langCode,
    required String direction,
    required String source,
    required String translated,
  }) async {
    _memoryPut(key, translated);
    final store = _store;
    if (store == null) return;
    try {
      await store.save(
        cacheKey: key,
        langCode: langCode,
        direction: direction,
        modelTag: _modelTag,
        sourceText: source,
        translatedText: translated,
      );
    } catch (e) {
      debugPrint('TRANSLATION CACHE save failed (ignored): $e');
    }
  }

  void _memoryPut(String key, String value) {
    _memory.remove(key);
    _memory[key] = value;
    if (_memory.length > _memoryCap) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// Local-language student text → English, for the tutor.
  Future<TranslationOutcome> toEnglishDetailed(
    String text,
    String fromLanguageCode, {
    TokenCallback? onToken,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || fromLanguageCode == 'en') {
      return TranslationOutcome.passthrough(text);
    }
    // Students often type English even when the UI is in another language.
    // Skip a full model round-trip in that case — it is the largest delay.
    if (looksLikeEnglish(trimmed)) {
      return TranslationOutcome.passthrough(text);
    }
    final islands = protectMathIslands(trimmed);
    final source = islands.text.trim().isEmpty ? trimmed : islands.text;
    final out = await _translate(
      text: source,
      fromName: chatTranslatePromptName(fromLanguageCode),
      toName: 'English',
      toCode: 'en',
      direction: 'to_en',
      cacheLangCode: fromLanguageCode,
      onToken: onToken,
    );
    if (!out.translated) return out;
    final restored = islands.restore(out.text);
    if (onToken != null && restored != out.text) {
      await emitToken(onToken, restored);
    }
    return TranslationOutcome(
      text: restored,
      translated: true,
      fromCache: out.fromCache,
    );
  }

  /// English tutor text → the student's learning language.
  ///
  /// Whole-text first (cache-friendly). If that is rejected or the engine
  /// stalls, each sentence is translated on its own so one failure cannot
  /// blank the rest of the reply.
  Future<TranslationOutcome> fromEnglishDetailed(
    String text,
    String toLanguageCode, {
    TokenCallback? onToken,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || toLanguageCode == 'en') {
      return TranslationOutcome.passthrough(text);
    }
    final islands = protectMathIslands(trimmed);
    if (islands.isPureMath) {
      return TranslationOutcome(
        text: repairUnclosedMathDelimiters(trimmed),
        translated: true,
      );
    }
    final source = islands.text.trim().isEmpty ? trimmed : islands.text;
    final whole = await _translate(
      text: source,
      fromName: 'English',
      toName: chatTranslatePromptName(toLanguageCode),
      toCode: toLanguageCode,
      direction: 'from_en',
      cacheLangCode: toLanguageCode,
      onToken: onToken,
    );
    if (whole.translated) {
      return TranslationOutcome(
        text: islands.restore(whole.text),
        translated: true,
        fromCache: whole.fromCache,
      );
    }
    final recovered = await _translatePiecewise(
      source,
      toLanguageCode,
    );
    if (recovered.translated) {
      final restored = islands.restore(recovered.text);
      await emitToken(onToken, restored);
      return TranslationOutcome(text: restored, translated: true);
    }
    return whole;
  }

  Future<TranslationOutcome> _translatePiecewise(
    String text,
    String toLanguageCode,
  ) async {
    final units = splitTranslationUnits(text);
    if (units.length <= 1) {
      return TranslationOutcome.passthrough(text);
    }
    final pieces = <String>[];
    var ok = 0;
    for (final unit in units) {
      final outcome = await _translate(
        text: unit,
        fromName: 'English',
        toName: chatTranslatePromptName(toLanguageCode),
        toCode: toLanguageCode,
        direction: 'from_en',
        cacheLangCode: toLanguageCode,
      );
      if (outcome.translated) {
        ok++;
        pieces.add(outcome.text);
      } else {
        pieces.add(outcome.text);
      }
    }
    if (ok == 0) {
      return TranslationOutcome(
        text: text,
        translated: false,
        failure: 'every sentence failed to translate',
      );
    }
    final joined = pieces.join(' ').trim();
    return TranslationOutcome(text: joined, translated: true);
  }

  /// Text-only wrapper. Prefer [toEnglishDetailed] where the caller can act
  /// on a failure — this one cannot distinguish a translation from a
  /// fallback.
  Future<String> toEnglish(String text, String fromLanguageCode) async =>
      (await toEnglishDetailed(text, fromLanguageCode)).text;

  /// Text-only wrapper. Prefer [fromEnglishDetailed].
  Future<String> fromEnglish(
    String text,
    String toLanguageCode, {
    TokenCallback? onToken,
  }) async =>
      (await fromEnglishDetailed(text, toLanguageCode, onToken: onToken)).text;

  /// Translates a tutor reply and its follow-up prompt.
  ///
  /// These used to go out as one call with `A:`/`B:` labels to save a model
  /// round-trip, and the reply was recovered with a regex. AfriSLM was
  /// trained on single-text translation only, so a two-part labelled prompt
  /// is off-distribution: the model can drop a label, translate the labels
  /// themselves, or merge the parts — and the regex then silently fell back
  /// to English. Two plain calls are slower and correct. Most follow-ups are
  /// static l10n strings that never reach here at all (see ChatNotifier),
  /// and the ones that do repeat verbatim across turns, so after the first
  /// occurrence the cache answers them without touching the model.
  Future<(TranslationOutcome reply, TranslationOutcome followUp)>
      fromEnglishPairDetailed(
    String reply,
    String followUp,
    String toLanguageCode,
  ) async {
    if (toLanguageCode == 'en') {
      return (
        TranslationOutcome.passthrough(reply),
        TranslationOutcome.passthrough(followUp),
      );
    }
    final translatedReply = await fromEnglishDetailed(reply, toLanguageCode);
    if (followUp.trim().isEmpty) {
      return (translatedReply, TranslationOutcome.passthrough(followUp));
    }
    return (
      translatedReply,
      await fromEnglishDetailed(followUp, toLanguageCode),
    );
  }

  /// Text-only wrapper for [fromEnglishPairDetailed].
  Future<(String reply, String followUp)> fromEnglishPair(
    String reply,
    String followUp,
    String toLanguageCode,
  ) async {
    final (r, f) =
        await fromEnglishPairDetailed(reply, followUp, toLanguageCode);
    return (r.text, f.text);
  }

  /// Output budget for one translation call.
  ///
  /// This used to clamp at 120 tokens while the tutor generates replies at
  /// maxTokens: 280, so any full-length answer was guaranteed to be cut off
  /// mid-sentence - and if the truncated output stripped down to nothing,
  /// the caller silently fell back to the English original. The ceiling has
  /// to sit above what the tutor can produce, not below it.
  ///
  /// The multiplier is 3x rather than 2x because the African languages here
  /// tokenize far less efficiently than English in this vocabulary: the same
  /// sentence routinely costs more tokens coming out than going in.
  int _tokenBudget(String text) {
    final words = text.split(RegExp(r'\s+')).length;
    final n = words * 3 + 32;
    if (n < 64) return 64;
    if (n > 512) return 512;
    return n;
  }
}
