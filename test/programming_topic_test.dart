import 'package:ai_connect_africa/ai_core/tutor/programming_topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Python, websites and apps are programming', () {
    expect(looksLikeProgramming('Teach me Python print()'), isTrue);
    expect(looksLikeProgramming('How do I make a website in HTML?'), isTrue);
    expect(looksLikeProgramming('Build a Flutter mobile app'), isTrue);
    expect(isProgrammingSubjectId('programming'), isTrue);
    expect(isProgrammingSubjectId('web_development'), isTrue);
    expect(isProgrammingSubjectId('biology'), isFalse);
  });

  test('science questions stay on the 0.6B brain', () {
    expect(looksLikeProgramming('What is photosynthesis?'), isFalse);
    expect(looksLikeProgramming('Solve 4x - 15 = 12'), isFalse);
  });

  test('curriculum coding opener names the lesson', () {
    expect(codingLessonChatOpener('Loops'), contains('Loops'));
    expect(codingLessonChatOpener('Loops'), contains('tiny code example'));
    expect(
      codingLessonChatOpener(''),
      contains('learn programming from the curriculum'),
    );
  });
}
