import 'package:ai_connect_africa/ai_core/science/science_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protectMathIslands keeps Kinyarwanda commands for AfriSLM', () {
    final islands = protectMathIslands('Shaka agaciro ka 4x - 15');
    expect(islands.isPureMath, isFalse);
    expect(islands.text, contains('Shaka'));
    expect(islands.text, isNot(contains('4x')));
    expect(islands.restore(islands.text), contains('4x'));
  });

  test('pure equations and formulas are math-only islands', () {
    expect(protectMathIslands('x = 2').isPureMath, isTrue);
    expect(protectMathIslands('CO2').isPureMath, isTrue);
    expect(protectMathIslands('H2O').isPureMath, isTrue);
    expect(protectMathIslands(r'$E = mc^2$').isPureMath, isTrue);
    expect(protectMathIslands('H_{2}O').isPureMath, isTrue);
    expect(protectMathIslands('x²').isPureMath, isTrue);
  });

  test('isMathPassThrough skips formulas and LaTeX', () {
    expect(isMathPassThrough('x = 2'), isTrue);
    expect(isMathPassThrough('H2O'), isTrue);
    expect(isMathPassThrough('CO2'), isTrue);
    expect(isMathPassThrough(r'$E = mc^2$'), isTrue);
    expect(isMathPassThrough(r'$$ 4x - 15 = 12x $$'), isTrue);
    expect(isMathPassThrough('4x/3-5=6+4x'), isTrue);
    expect(isMathPassThrough('Plants make food.'), isFalse);
    expect(isMathPassThrough('Shaka agaciro ka 4x - 15'), isFalse);
  });

  test('fenced code skips AfriSLM', () {
    expect(
      isMathPassThrough('```python\nprint("hi")\n```'),
      isTrue,
    );
    final islands = protectMathIslands(
      'Here is a loop:\n```python\nfor i in range(3):\n    print(i)\n```\nTry it.',
    );
    expect(islands.text, contains('Here is a loop'));
    expect(islands.text, isNot(contains('print')));
    expect(islands.restore(islands.text), contains('print(i)'));
  });

  test('repairUnclosedMathDelimiters closes leaked \$\$', () {
    expect(repairUnclosedMathDelimiters(r'$$ 4x - 15').contains(r'$$'), isTrue);
    final painted = repairUnclosedMathDelimiters(r'$$ 4x - 15');
    expect(RegExp(r'\$\$').allMatches(painted).length.isEven, isTrue);
  });

  test('splitScienceSpans separates TeX from prose', () {
    final spans = splitScienceSpans(r'Water is $H_2O$ today.');
    expect(spans.any((s) => s.isMath), isTrue);
    expect(spans.any((s) => !s.isMath && s.text.contains('Water')), isTrue);
  });

  test('splitScienceSpans does not treat \$ inside fences as math', () {
    final spans = splitScienceSpans('```js\nconst price = \$5;\n```\nTry it.');
    expect(spans.any((s) => s.isMath), isFalse);
    expect(spans.any((s) => s.text.contains(r'$5')), isTrue);
    expect(spans.any((s) => !s.isMath && s.text.contains('Try it')), isTrue);
  });

  test('splitScienceSpans keeps Markdown prose out of KaTeX', () {
    const md = '**Key idea**\n\n- First point\n- Second point\n\nTry this next.';
    final spans = splitScienceSpans(md);
    expect(spans, hasLength(1));
    expect(spans.single.isMath, isFalse);
    expect(spans.single.text, contains('**Key idea**'));
    expect(spans.single.text, contains('- First point'));
  });

  group('stripBareLatexCommands', () {
    test('unwraps a bare \\text{}_N chemistry formula to clean Unicode', () {
      expect(
        stripBareLatexCommands(r'\text{6CO}_2 + \text{6H}_2\text{O}'),
        '6CO₂ + 6H₂O',
      );
    });

    test('leaves \\text{} with no subscript as plain content', () {
      expect(stripBareLatexCommands(r'\text{glucose}'), 'glucose');
    });

    test('is a no-op when there is no bare \\text{} to unwrap', () {
      expect(stripBareLatexCommands('Plants make food.'), 'Plants make food.');
    });

    test('formatScienceProse strips the raw clutter a model can leak into '
        'prose outside \$...\$', () {
      final out =
          formatScienceProse(r'The reaction is \text{6CO}_2 + \text{6H}_2\text{O}.');
      expect(out, isNot(contains(r'\text')));
      expect(out, isNot(contains(r'\')));
      expect(out, contains('6CO₂'));
      expect(out, contains('6H₂O'));
    });

    test('formatScienceProse cleans a whole bare equation: underscore '
        'subscript chains and a bare \\rightarrow, with no leftover '
        'backslash or underscore', () {
      final out = formatScienceProse(
          r'6CO_2 + 6H_2O \rightarrow C_6H_{12}O_6 + 6O_2');
      expect(out, isNot(contains(r'\')));
      expect(out, isNot(contains('_')));
      expect(out, contains('C₆H₁₂O₆'));
      expect(out, contains('→'));
    });

    test('a bare symbol command is matched whole, not as a substring of a '
        'longer command it prefixes', () {
      final out = formatScienceProse(r'x \leq 5, \left(y\right)');
      expect(out, contains('≤ 5'));
      expect(out, isNot(contains('≤q')));
      expect(out, isNot(contains('≤ft')));
      // \left/\right are real KaTeX delimiter commands, not in the bare
      // symbol table — left as-is here rather than guessed at, since this
      // function only runs on prose/fallback text, never inside a live
      // math span where KaTeX itself renders them.
      expect(out, contains(r'\left'));
    });
  });

  group('applyLatexChemistryUnicode', () {
    test('converts a multi-element underscore chain in one pass', () {
      expect(applyLatexChemistryUnicode(r'C_6H_{12}O_6'), 'C₆H₁₂O₆');
    });

    test('leaves an element run with no subscript alone', () {
      expect(applyLatexChemistryUnicode('CoP'), 'CoP');
    });

    test('is a no-op with no underscore present', () {
      expect(applyLatexChemistryUnicode('Plants make food.'),
          'Plants make food.');
    });
  });
}
