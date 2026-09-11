import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/ai_core/translate/translation_quality.dart';

/// Every case here is a shape AfriSLM has actually produced, or a correct
/// translation that must not be mistaken for one. The point of the validator
/// is to keep the first group off the screen without throwing away the
/// second, so both are tested.
void main() {
  group('cleanTranslationOutput', () {
    test('strips a complete think span', () {
      expect(
        cleanTranslationOutput('<think>hmm, Swahili</think>Habari yako'),
        'Habari yako',
      );
    });

    test('strips a stray closing think tag and everything before it', () {
      expect(
        cleanTranslationOutput('reasoning noise</think>Habari yako'),
        'Habari yako',
      );
    });

    test('strips a leading label without touching the translation', () {
      expect(cleanTranslationOutput('Translation: Habari yako'), 'Habari yako');
      expect(cleanTranslationOutput('Output - Habari yako'), 'Habari yako');
    });

    test('strips wrapping quotes', () {
      expect(cleanTranslationOutput('"Habari yako"'), 'Habari yako');
      expect(cleanTranslationOutput('\u201cHabari yako\u201d'), 'Habari yako');
    });

    test('leaves a clean translation alone', () {
      expect(cleanTranslationOutput('Habari yako'), 'Habari yako');
    });

    test('strips an echoed /no_think control marker', () {
      // Observed from both backends in the 3-clause benchmark: the marker
      // comes from our own user prompt and must never reach a student.
      expect(
        cleanTranslationOutput('Maji husafiri juu kutoka mizizi. /no_think'),
        'Maji husafiri juu kutoka mizizi.',
      );
      expect(
        cleanTranslationOutput('/no_think\nHabari yako'),
        'Habari yako',
      );
    });

    test('a marker-only reply cleans to empty and is rejected, not cached', () {
      // Stripping runs before judging, so this is the path where a cleaned
      // candidate could reach _cacheSave as a "successful" empty translation.
      final cleaned = cleanTranslationOutput('/no_think');
      expect(cleaned, isEmpty);
      expect(
        judgeTranslation(
          source: 'Water travels up from the roots.',
          candidate: cleaned,
          toCode: 'sw',
        ),
        TranslationRejection.empty,
      );
    });

    test('leaves a slash that is not the control marker alone', () {
      // 19 orthographies we cannot reason about — the pattern must match the
      // literal /no_think marker, nothing near it.
      expect(cleanTranslationOutput('Ni 50/50 kati yao'), 'Ni 50/50 kati yao');
      expect(cleanTranslationOutput('Habari / no think'), 'Habari / no think');
    });

    test('does not strip an internal quote pair', () {
      expect(
        cleanTranslationOutput('Neno "mimea" linamaanisha plants'),
        'Neno "mimea" linamaanisha plants',
      );
    });
  });

  group('judgeTranslation accepts good output', () {
    test('a plain Swahili translation', () {
      expect(
        judgeTranslation(
          source: 'Photosynthesis is how a plant makes food from sunlight.',
          candidate:
              'Usanisinuru ni jinsi mmea unavyotengeneza chakula kutokana na '
              'mwanga wa jua.',
          toCode: 'sw',
        ),
        isNull,
      );
    });

    test('a short answer with no English markers', () {
      expect(
        judgeTranslation(source: 'Yes', candidate: 'Ndiyo', toCode: 'sw'),
        isNull,
      );
    });

    test('a translation into English (the toEnglish direction)', () {
      expect(
        judgeTranslation(
          source: 'Habari yako',
          candidate: 'How are you',
          toCode: 'en',
        ),
        isNull,
      );
    });

    test('a long correct translation carrying an English technical term', () {
      // The stillEnglish check is the weakest signal and must not fire on a
      // real translation that embeds loanwords.
      expect(
        judgeTranslation(
          source:
              'The cell membrane controls what enters and leaves the cell in '
              'the body of a living organism.',
          candidate:
              'Utando wa seli hudhibiti kinachoingia na kutoka kwenye seli '
              'katika mwili wa kiumbe hai chenye uhai.',
          toCode: 'sw',
        ),
        isNull,
      );
    });
  });

  group('judgeTranslation rejects invented output', () {
    test('empty', () {
      expect(
        judgeTranslation(source: 'Hello', candidate: '   ', toCode: 'sw'),
        TranslationRejection.empty,
      );
    });

    test('echoed instruction', () {
      expect(
        judgeTranslation(
          source: 'Hello there',
          candidate:
              'Please translate the following English text into Swahili: '
              'Hello there.',
          toCode: 'sw',
        ),
        TranslationRejection.echoedPrompt,
      );
    });

    test('commentary preamble', () {
      expect(
        judgeTranslation(
          source: 'Hello there',
          candidate: 'Sure! Here is the translation you asked for: Habari',
          toCode: 'sw',
        ),
        TranslationRejection.echoedPrompt,
      );
    });

    test('persona leak', () {
      expect(
        judgeTranslation(
          source: 'Hello there',
          candidate: 'You are a professional English to Swahili translator.',
          toCode: 'sw',
        ),
        TranslationRejection.echoedPrompt,
      );
    });

    test('input returned unchanged', () {
      expect(
        judgeTranslation(
          source: 'Photosynthesis is how a plant makes food.',
          candidate: 'Photosynthesis is how a plant makes food.',
          toCode: 'sw',
        ),
        TranslationRejection.unchanged,
      );
    });

    test('input returned unchanged apart from punctuation and case', () {
      expect(
        judgeTranslation(
          source: 'Photosynthesis is how a plant makes food.',
          candidate: 'photosynthesis is how a plant makes food',
          toCode: 'sw',
        ),
        TranslationRejection.unchanged,
      );
    });

    test('decoder loop', () {
      expect(
        judgeTranslation(
          source: 'The plant makes food from sunlight in its green leaves.',
          candidate: 'mmea hutengeneza chakula ' * 8,
          toCode: 'sw',
        ),
        TranslationRejection.repetitionLoop,
      );
    });

    test('runaway length', () {
      expect(
        judgeTranslation(
          source: 'The plant makes food.',
          candidate: List.generate(200, (i) => 'neno$i').join(' '),
          toCode: 'sw',
        ),
        anyOf(
          TranslationRejection.lengthBlowup,
          TranslationRejection.repetitionLoop,
        ),
      );
    });

    test('still English when the target is not English', () {
      expect(
        judgeTranslation(
          source: 'A plant uses light to make its own food inside the leaf.',
          candidate:
              'The plant is using the light that it can find in the leaf to '
              'make food for itself.',
          toCode: 'sw',
        ),
        TranslationRejection.stillEnglish,
      );
    });

    test('rejects Hebrew / mixed-script gibberish for Kinyarwanda', () {
      expect(
        judgeTranslation(
          source: 'Do you understand so far?',
          candidate: 'all põse sorry me know tenceara השי Let questions ?',
          toCode: 'rw',
        ),
        TranslationRejection.garbledScript,
      );
    });

    test('the English check is skipped on a retry', () {
      // Same candidate as above, but with strictEnglishCheck off it must be
      // accepted — a second rejection would cost the student the
      // translation entirely.
      expect(
        judgeTranslation(
          source: 'A plant uses light to make its own food inside the leaf.',
          candidate:
              'The plant is using the light that it can find in the leaf to '
              'make food for itself.',
          toCode: 'sw',
          strictEnglishCheck: false,
        ),
        isNull,
      );
    });
  });

  group('hasRepetitionLoop', () {
    test('ignores short text', () {
      expect(hasRepetitionLoop('ndiyo ndiyo ndiyo'), isFalse);
    });

    test('ignores natural repetition', () {
      expect(
        hasRepetitionLoop(
          'Mmea hutengeneza chakula kutokana na mwanga wa jua na maji '
          'kutoka kwenye udongo na hewa ya kaboni dioksidi kutoka angani.',
        ),
        isFalse,
      );
    });

    test('catches a looped phrase', () {
      expect(hasRepetitionLoop('chakula kutokana na mwanga ' * 6), isTrue);
    });
  });

  group('modelTagFor', () {
    test('changes when the model file changes', () {
      final a = modelTagFor(path: r'C:\OTIC\translate-afrislm.gguf', sizeBytes: 672329792);
      final b = modelTagFor(path: r'C:\OTIC\translate-afrislm.gguf', sizeBytes: 512000000);
      expect(a, isNot(b));
    });

    test('is stable across directories so a moved file keeps its cache', () {
      final a = modelTagFor(path: r'C:\OTIC\translate-afrislm.gguf', sizeBytes: 10);
      final b = modelTagFor(path: '/home/pi/OTIC/translate-afrislm.gguf', sizeBytes: 10);
      expect(a, b);
    });
  });

  group('splitTranslationUnits', () {
    test('keeps a short title in one piece', () {
      expect(splitTranslationUnits('Write the equation'), ['Write the equation']);
    });

    test('splits a two-sentence tutor reply', () {
      const text =
          'Photosynthesis is how a plant makes food from sunlight. '
          'The leaf takes in carbon dioxide.';
      final units = splitTranslationUnits(text);
      expect(units, hasLength(2));
      expect(units.first, contains('Photosynthesis'));
      expect(units.last, contains('leaf'));
    });
  });
}
