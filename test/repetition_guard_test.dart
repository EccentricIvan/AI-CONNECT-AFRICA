import 'package:ai_connect_africa/ai_core/inference/repetition_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [text] a few characters at a time, the way tokens arrive.
({String shown, bool tripped}) run(String text, {int step = 3}) {
  final guard = RepetitionGuard();
  final shown = StringBuffer();
  for (var i = 0; i < text.length && !guard.tripped; i += step) {
    final end = i + step > text.length ? text.length : i + step;
    shown.write(guard.add(text.substring(i, end)));
  }
  shown.write(guard.flush());
  expect(shown.toString(), guard.text, reason: 'streamed == returned');
  return (shown: shown.toString(), tripped: guard.tripped);
}

void main() {
  // The loop a learner saw on the Windows build (Qwen2.5-Coder-1.5B).
  const p1 =
      'The concept of matter being called to occupy space is a fundamental '
      'principle in physics and chemistry. Matter is defined as anything that '
      'has mass and takes up space. This principle is based on the idea that '
      'matter is composed of atoms and molecules, which are themselves '
      'composed of subatomic particles.';
  const p2 =
      'The idea of matter occupying space is a fundamental concept in physics '
      'and chemistry. Matter is defined as anything that has mass and takes up '
      'space. This principle is based on the idea that matter is composed of '
      'atoms and molecules, which are themselves composed of subatomic '
      'particles.';

  test('the looping answer stops before the repeat is ever shown', () {
    final r = run('$p1\n\n$p2\n\n$p2\n\n$p2\n\n$p2');
    expect(r.tripped, isTrue);
    expect(r.shown, startsWith(p1));
    expect(
      'Matter is defined as anything'.allMatches(r.shown).length,
      1,
      reason: 'the repeated sentence must not reach the student',
    );
    expect(r.shown.length, lessThan(p1.length + p2.length));
  });

  test('a normal answer streams through unchanged', () {
    const answer =
        'Matter is anything that has mass and takes up space. A rock, water '
        'and the air you breathe are all matter.\n\nTry this: name three '
        'things in your classroom that are matter, and one thing that is not.';
    final r = run(answer);
    expect(r.tripped, isFalse);
    expect(r.shown, answer);
  });

  test('a sentence that starts like an earlier one but differs is released',
      () {
    const answer =
        'Plants make their own food using sunlight and water. Plants make '
        'their own oxygen as a by-product of that same process.';
    final r = run(answer);
    expect(r.tripped, isFalse);
    expect(r.shown, answer);
  });

  test('short repeated sentences are fine', () {
    const answer = 'Good. Now try the next one. Good. Now the last one.';
    expect(run(answer).shown, answer);
  });

  test('repeated lines inside a code fence are not a loop', () {
    const answer =
        'Here is a loop that prints the same message on every pass:\n'
        '```python\n'
        'print("the value of x is now being printed here")\n'
        'print("the value of x is now being printed here")\n'
        '```\n'
        'Run it and see what happens.';
    final r = run(answer);
    expect(r.tripped, isFalse);
    expect(r.shown, answer);
  });

  test('HTML and JSON output is never guarded', () {
    const html =
        '<ul>\n<li>A card that describes this product in detail.</li>\n'
        '<li>A card that describes this product in detail.</li>\n</ul>';
    expect(run(html).shown, html);
    const json =
        '[{"q": "Which of these is matter made of in the end?"},\n'
        '{"q": "Which of these is matter made of in the end?"}]';
    expect(run(json).shown, json);
  });
}
