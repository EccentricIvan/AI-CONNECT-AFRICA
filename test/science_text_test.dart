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
}
