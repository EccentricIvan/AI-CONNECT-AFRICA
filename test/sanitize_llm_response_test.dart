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

    test('hides a whole-reply monologue with no answer paragraph', () {
      expect(
        sanitizeLLMResponse(
          'Okay, the user is asking, "What is 2 plus 2?" Let me think. 2 plus',
        ),
        isEmpty,
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
