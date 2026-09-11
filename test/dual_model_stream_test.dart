import 'package:ai_connect_africa/ai_core/inference/stream_cascade.dart';
import 'package:ai_connect_africa/ai_core/science/science_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('math and markdown clauses skip AfriSLM', () {
    expect(isMathPassThrough('x = 2'), isTrue);
    expect(isMathPassThrough(r'$E = mc^2$'), isTrue);
    expect(isMathPassThrough('H2O'), isTrue);
    expect(isMathPassThrough('Plants make food.'), isFalse);
  });

  test('EnglishIngestBuffer seals on close', () async {
    final buf = EnglishIngestBuffer();
    buf.add('Hello');
    buf.close();
    expect(await buf.waitForReasoningPrompt(), 'Hello');
  });
}
