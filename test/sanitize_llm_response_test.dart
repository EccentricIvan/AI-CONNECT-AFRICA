import 'package:ai_connect_africa/ai_core/inference/sanitize_llm_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeLLMResponse', () {
    test('passes a normal tutor reply through', () {
      expect(
        sanitizeLLMResponse('Photosynthesis is how plants make food.'),
        'Photosynthesis is how plants make food.',
      );
    });

    test('removes a closed think block', () {
      expect(
        sanitizeLLMResponse(
          '<think>plan the answer</think>\n\nPlants use sunlight.',
        ),
        'Plants use sunlight.',
      );
    });

    test('keeps only text after an unmatched closing think tag', () {
      expect(
        sanitizeLLMResponse('hidden reasoning</think>\nThe water cycle repeats.'),
        'The water cycle repeats.',
      );
    });

    test('strips the Okay lets see preamble before the answer', () {
      expect(
        sanitizeLLMResponse(
          "Okay, let's see what they need.\n\nUse a number line.",
        ),
        'Use a number line.',
      );
    });

    test('strips The student is asking preamble', () {
      expect(
        sanitizeLLMResponse(
          'The student is asking about fractions.\n\nA fraction is a part of a whole.',
        ),
        'A fraction is a part of a whole.',
      );
    });

    test('strips The user wants preamble', () {
      expect(
        sanitizeLLMResponse(
          'The user wants help with fractions.\n\n'
          'A fraction is a part of a whole.',
        ),
        'A fraction is a part of a whole.',
      );
    });

    test('strips I need to planning preamble', () {
      expect(
        sanitizeLLMResponse(
          'I need to explain photosynthesis carefully.\n\n'
          'Plants turn sunlight into food.',
        ),
        'Plants turn sunlight into food.',
      );
    });

    test('hides a whole-reply monologue with no answer paragraph', () {
      expect(
        sanitizeLLMResponse(
          'Okay, the user is asking, "What is 2 plus 2?" Let me think. 2 plus',
        ),
        isEmpty,
      );
    });

    test('drops first-paragraph reasoning when later answer exists', () {
      expect(
        sanitizeLLMResponse(
          'Looking at this question about water.\n\n'
          'Water evaporates, then rains back down.',
        ),
        'Water evaporates, then rains back down.',
      );
    });

    test('strips /no_think leftover', () {
      expect(
        sanitizeLLMResponse('Plants make food. /no_think'),
        'Plants make food.',
      );
    });

    test('drops an unclosed think span', () {
      expect(
        sanitizeLLMResponse('<think>still planning the lesson'),
        isEmpty,
      );
      expect(
        sanitizeLLMResponse('Intro.\n\n<think>more planning'),
        'Intro.',
      );
    });
  });

  group('SanitizedTokenStream', () {
    test('holds a think span and then streams the answer', () {
      final stream = SanitizedTokenStream();
      expect(stream.add('<think>plan</think>\n\n'), isEmpty);
      expect(stream.add('Plants '), 'Plants ');
      expect(stream.add('use sunlight.'), 'use sunlight.');
      expect(stream.text, 'Plants use sunlight.');
    });

    test('does not emit a bare Okay-the-user-is-asking monologue', () {
      final stream = SanitizedTokenStream();
      expect(
        stream.add('Okay, the user is asking, "What is 2 plus 2?"'),
        isEmpty,
      );
      expect(stream.flush(), isEmpty);
      expect(stream.text, isEmpty);
    });

    test('releases the answer after a lets-see preamble', () {
      final stream = SanitizedTokenStream();
      expect(stream.add("Okay, let's see.\n\n"), isEmpty);
      expect(stream.add('Start with the ones place.'), 'Start with the ones place.');
      expect(stream.text, 'Start with the ones place.');
    });
  });
}
