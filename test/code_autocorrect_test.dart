import 'package:ai_connect_africa/shared/coding/code_autocorrect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('python heuristics fix common typos and quotes', () {
    const broken = '''
pritn("Hello)
name = "Alice
if x = 1:
    print(x
''';
    final fixed = applyHeuristicAutocorrect(broken, CodeAutocorrectKind.python);
    expect(fixed, contains('print("Hello")'));
    expect(fixed, contains('name = "Alice"'));
    expect(fixed, contains('if x == 1:'));
    expect(fixed, contains('print(x)'));
  });

  test('html heuristics close open tags and normalize doctype', () {
    const broken = '''
<!doctype html>
<html>
<head><title>Hi</title>
<body>
<p>Hello
''';
    final fixed = applyHeuristicAutocorrect(broken, CodeAutocorrectKind.html);
    expect(fixed, contains('<!DOCTYPE html>'));
    expect(fixed, contains('</p>'));
    expect(fixed, contains('</body>'));
    expect(fixed, contains('</html>'));
  });

  test('extractCorrectedCode strips fences', () {
    const raw = '```python\nprint("ok")\n```';
    expect(extractCorrectedCode(raw), 'print("ok")');
  });
}
