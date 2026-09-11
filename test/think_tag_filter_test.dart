import 'package:ai_connect_africa/ai_core/inference/think_tag_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [tokens] through a filter the way the LiteRT stream does and
/// returns everything a student would have seen.
String run(List<String> tokens) {
  final filter = ThinkTagFilter();
  final seen = StringBuffer();
  for (final token in tokens) {
    seen.write(filter.add(token));
  }
  seen.write(filter.flush());
  return seen.toString();
}

void main() {
  group('ThinkTagFilter', () {
    test('passes an ordinary reply through untouched', () {
      expect(
        run(['Photo', 'synthesis', ' is how', ' plants eat.']),
        'Photosynthesis is how plants eat.',
      );
    });

    test('drops the empty block /no_think leaves behind', () {
      // The exact shape observed from Qwen-family models once the switch is
      // honoured: an open/close pair with nothing but newlines inside.
      expect(
        run(['<think>', '\n\n', '</think>', '\n\n', 'Plants use sunlight.']),
        'Plants use sunlight.',
      );
    });

    test('drops a real reasoning span when the switch is ignored', () {
      expect(
        run([
          '<think>',
          'The student asked about photosynthesis. ',
          'I should start simple.',
          '</think>',
          'Photosynthesis is how a plant makes food.',
        ]),
        'Photosynthesis is how a plant makes food.',
      );
    });

    test('handles a tag split across several tokens', () {
      // Tokenisers routinely break `<think>` into `<`, `think`, `>`.
      expect(
        run(['<', 'think', '>', 'reasoning', '</', 'think', '>', 'Answer.']),
        'Answer.',
      );
    });

    test('does not swallow text that merely starts with a less-than sign', () {
      expect(run(['<', ' 5 is less than 10']), '< 5 is less than 10');
    });

    test('keeps angle-bracket content that is not a think tag', () {
      expect(run(['<b>', 'bold', '</b>']), '<b>bold</b>');
    });

    test('streams progressively rather than holding the whole reply', () {
      final filter = ThinkTagFilter();
      expect(filter.add('<think>'), isEmpty);
      expect(filter.add('hmm'), isEmpty);
      expect(filter.add('</think>'), isEmpty);
      // Once the span closes, later tokens must flow one at a time — a
      // filter that buffered to the end would make streaming pointless.
      expect(filter.add('Plants '), 'Plants ');
      expect(filter.add('make food.'), 'make food.');
    });

    test('salvages an unterminated span when nothing else was produced', () {
      // Qwen3 can burn the whole token budget inside a span it never closes.
      // Dropping it rendered the student a blank bubble; a rough answer beats
      // silence. Measured end-to-end on a Luganda follow-up.
      expect(
        run(['<think>', 'still thinking and then cut off']),
        'still thinking and then cut off',
      );
    });

    test('releases held whitespace once real text arrives', () {
      expect(run(['\n', '\n', 'Answer.']), '\n\nAnswer.');
    });

    group('/no_think marker', () {
      // The tutor prompt carries this switch. If LiteRT-LM's Qwen3 template
      // echoes it back instead of consuming it, it must not surface — the
      // same artifact already had to be stripped from translation output.
      test('is dropped when echoed at the end of a reply', () {
        // The space that preceded the marker survives; only the marker has
        // to go, and trailing whitespace is invisible in the bubble.
        expect(
          run(['Plants make food.', ' /no_think']).trimRight(),
          'Plants make food.',
        );
      });

      test('is dropped when echoed before the answer', () {
        expect(run(['/no_think', 'Plants make food.']), 'Plants make food.');
      });

      test('is dropped when split across tokens', () {
        final out = run(['Plants make food.', ' /no', '_th', 'ink']);
        expect(out, isNot(contains('no_think')));
        expect(out.trimRight(), 'Plants make food.');
      });

      test('does not hold back text that merely contains a slash', () {
        expect(run(['Use 5/10', ' of it.']), 'Use 5/10 of it.');
      });
    });
  });
}
