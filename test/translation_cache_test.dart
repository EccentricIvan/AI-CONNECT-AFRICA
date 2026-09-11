import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/translate/translation_pipeline.dart';

/// Engine that returns a queued list of responses and counts how many times
/// it was actually asked to generate — which is the whole point of the
/// cache, and the only thing that makes a non-English turn fast.
class _ScriptedEngine extends InferenceEngine {
  _ScriptedEngine(this.responses);

  final List<String> responses;
  int calls = 0;
  final List<String> prompts = [];

  @override
  bool get isReady => true;

  @override
  String get backendLabel => 'Scripted';

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    prompts.add(prompt);
    final out = calls < responses.length ? responses[calls] : responses.last;
    calls++;
    onToken?.call(out);
    return out;
  }

  @override
  Future<void> dispose() async {}
}

class _ByPromptEngine extends InferenceEngine {
  int calls = 0;

  @override
  bool get isReady => true;

  @override
  String get backendLabel => 'ByPrompt';

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    calls++;
    // Whole-reply echo (rejected). Each sentence on its own is translated.
    if (prompt.contains('The leaf takes') &&
        prompt.contains('Photosynthesis is how')) {
      const echo =
          'Photosynthesis is how a plant makes food from sunlight. '
          'The leaf takes in carbon dioxide.';
      onToken?.call(echo);
      return echo;
    }
    if (prompt.contains('The leaf takes')) {
      const out = 'Jani huchukua dioksidi kabonia.';
      onToken?.call(out);
      return out;
    }
    const out =
        'Photosynthesis ni namna mmea unavyotengeneza chakula kutokana na jua.';
    onToken?.call(out);
    return out;
  }

  @override
  Future<void> dispose() async {}
}
class _BrokenEngine extends InferenceEngine {
  int calls = 0;

  @override
  bool get isReady => false;

  @override
  String get backendLabel => 'Broken';

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    calls++;
    throw StateError('native library failed to load');
  }

  @override
  Future<void> dispose() async {}
}

class _MemoryStore implements TranslationStore {
  final Map<String, ({String source, String translated})> rows = {};
  int lookups = 0;
  int saves = 0;

  @override
  Future<String?> lookup(String cacheKey, String expectedSource) async {
    lookups++;
    final row = rows[cacheKey];
    if (row == null) return null;
    if (row.source != expectedSource) return null; // collision guard
    return row.translated;
  }

  @override
  Future<void> save({
    required String cacheKey,
    required String langCode,
    required String direction,
    required String modelTag,
    required String sourceText,
    required String translatedText,
  }) async {
    saves++;
    rows[cacheKey] = (source: sourceText, translated: translatedText);
  }
}

/// A store whose every operation throws — a cache must never be able to
/// break a translation.
class _BrokenStore implements TranslationStore {
  @override
  Future<String?> lookup(String cacheKey, String expectedSource) async =>
      throw StateError('disk full');

  @override
  Future<void> save({
    required String cacheKey,
    required String langCode,
    required String direction,
    required String modelTag,
    required String sourceText,
    required String translatedText,
  }) async =>
      throw StateError('disk full');
}

void main() {
  group('translation cache', () {
    test('a repeat of the same text never reaches the model', () async {
      final engine = _ScriptedEngine(['Habari yako']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      final first = await pipeline.fromEnglishDetailed('How are you', 'sw');
      final second = await pipeline.fromEnglishDetailed('How are you', 'sw');

      expect(first.text, 'Habari yako');
      expect(second.text, 'Habari yako');
      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(engine.calls, 1, reason: 'second call must be served from cache');
    });

    test('a cache hit still streams through onToken', () async {
      final engine = _ScriptedEngine(['Habari yako']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      await pipeline.fromEnglishDetailed('How are you', 'sw');
      final streamed = <String>[];
      await pipeline.fromEnglishDetailed('How are you', 'sw',
          onToken: streamed.add);

      expect(streamed.join(), 'Habari yako');
    });

    test('whitespace differences share a cache row', () async {
      final engine = _ScriptedEngine(['Habari yako']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      await pipeline.fromEnglishDetailed('How  are   you', 'sw');
      await pipeline.fromEnglishDetailed('How are you', 'sw');
      expect(engine.calls, 1);
    });

    test('case differences do not share a cache row', () async {
      final engine = _ScriptedEngine(['Habari yako', 'HABARI YAKO']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      await pipeline.fromEnglishDetailed('How are you', 'sw');
      await pipeline.fromEnglishDetailed('HOW ARE YOU', 'sw');
      expect(engine.calls, 2);
    });

    test('a different language misses', () async {
      final engine = _ScriptedEngine(['Habari yako', 'Bawo ni']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      await pipeline.fromEnglishDetailed('How are you', 'sw');
      await pipeline.fromEnglishDetailed('How are you', 'yo');
      expect(engine.calls, 2);
    });

    test('the opposite direction misses', () async {
      final engine = _ScriptedEngine(['Habari yako', 'How are you']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      await pipeline.fromEnglishDetailed('How are you', 'sw');
      await pipeline.toEnglishDetailed('Habari yako', 'sw');
      expect(engine.calls, 2);
    });

    test('a different model file misses rather than serving stale rows',
        () async {
      final store = _MemoryStore();
      final engineA = _ScriptedEngine(['Habari yako']);
      await TranslationPipeline(engineA, store: store, modelTag: 'q4km:672329792')
          .fromEnglishDetailed('How are you', 'sw');

      final engineB = _ScriptedEngine(['Habari zako']);
      final second =
          await TranslationPipeline(engineB, store: store, modelTag: 'q4_0:512000000')
              .fromEnglishDetailed('How are you', 'sw');

      expect(engineB.calls, 1, reason: 're-quantized model must not reuse rows');
      expect(second.text, 'Habari zako');
    });

    test('a repeat hits in-memory cache with no store', () async {
      final engine = _ScriptedEngine(['Habari yako']);
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final first = await pipeline.fromEnglishDetailed('How are you', 'sw');
      final second = await pipeline.fromEnglishDetailed('How are you', 'sw');

      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(engine.calls, 1);
    });

    test('a broken cache does not break translation', () async {
      final engine = _ScriptedEngine(['Habari yako']);
      final pipeline =
          TranslationPipeline(engine, store: _BrokenStore(), modelTag: 't');

      final out = await pipeline.fromEnglishDetailed('How are you', 'sw');
      expect(out.text, 'Habari yako');
      expect(out.translated, isTrue);
    });

    test('a rejected translation is never cached', () async {
      final engine = _ScriptedEngine(['How are you', 'How are you']);
      final store = _MemoryStore();
      final pipeline =
          TranslationPipeline(engine, store: store, modelTag: 'test:1');

      await pipeline.fromEnglishDetailed('How are you', 'sw');
      expect(store.saves, 0, reason: 'invented output must not be persisted');
    });
  });

  group('never invent', () {
    test('an unchanged echo is retried, then falls back to the original',
        () async {
      final engine = _ScriptedEngine(['How are you', 'How are you']);
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.fromEnglishDetailed('How are you', 'sw');

      expect(engine.calls, 2, reason: 'one retry before giving up');
      expect(out.translated, isFalse);
      expect(out.text, 'How are you');
      expect(out.failure, contains('identical'));
    });

    test('a retry that succeeds is used', () async {
      final engine = _ScriptedEngine([
        'Please translate the following English text into Swahili',
        'Habari yako',
      ]);
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.fromEnglishDetailed('How are you', 'sw');

      expect(engine.calls, 2);
      expect(out.translated, isTrue);
      expect(out.text, 'Habari yako');
    });

    test('scaffolding is stripped rather than rejected', () async {
      final engine = _ScriptedEngine(['Translation: Habari yako']);
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.fromEnglishDetailed('How are you', 'sw');

      expect(engine.calls, 1, reason: 'a strippable label needs no retry');
      expect(out.text, 'Habari yako');
      expect(out.translated, isTrue);
    });
  });

  group('never fail the turn', () {
    test('an engine that always throws yields displayable English', () async {
      final engine = _BrokenEngine();
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.fromEnglishDetailed('How are you', 'sw');

      expect(out.text, 'How are you');
      expect(out.translated, isFalse);
      expect(out.failure, isNotNull);
    });

    test('the outgoing direction also survives a broken engine', () async {
      final engine = _BrokenEngine();
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.toEnglishDetailed('Habari yako', 'sw');

      expect(out.text, 'Habari yako');
      expect(out.translated, isFalse);
    });

    test('English input short-circuits without touching the model', () async {
      final engine = _ScriptedEngine(['should not be used']);
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.toEnglishDetailed(
        'What is the way to explain this for my class',
        'sw',
      );

      expect(engine.calls, 0);
      expect(out.text, 'What is the way to explain this for my class');
    });

    test('a rejected whole reply is recovered sentence by sentence', () async {
      const source =
          'Photosynthesis is how a plant makes food from sunlight. '
          'The leaf takes in carbon dioxide.';
      final engine = _ByPromptEngine();
      final pipeline = TranslationPipeline(engine, modelTag: 't');

      final out = await pipeline.fromEnglishDetailed(source, 'sw');

      expect(out.translated, isTrue);
      expect(out.text, contains('Jani'));
      expect(out.text, isNot(equals(source)));
      expect(engine.calls, greaterThan(2));
    });
  });
}
