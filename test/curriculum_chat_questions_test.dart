import 'package:ai_connect_africa/ai_core/tutor/school_math.dart';
import 'package:ai_connect_africa/ai_core/tutor/programming_topic.dart';
import 'package:ai_connect_africa/curriculum/curriculum_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Questions a student would type, taken from curriculum quiz/example wording.
const kCurriculumChatQuestions = <String>[
  'Convert 1010₂ to base 10.',
  'Convert 1010 binary to denary',
  'What is 45% of 200?',
  'What is 3/4 of 80?',
  'Solve 2x + 3 = 11',
  'What is photosynthesis in green plants?',
  'What are the two products of photosynthesis?',
  'Convert 5000g to kilograms.',
  'Which branch of physics studies forces and motion?',
  'What is a number base, and why does it matter?',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curriculum chat questions match a lesson (or are school-math)', () async {
    final svc = CurriculumService();
    await svc.loadAll();

    for (final q in kCurriculumChatQuestions) {
      final match = svc.findBestMatchDetailed(q);
      final math = solveSchoolMath(q);
      // ignore: avoid_print
      print('${match == null ? "NO LESSON" : "${match.subjectName} / ${match.lesson.title}"}'
          '${math == null ? "" : "  [math → ${math.answer}]"}'
          '  ←  $q');
    }

    expect(
      svc.findBestMatchDetailed('What is photosynthesis in green plants?')?.lesson.title,
      'Nutrition in Green Plants',
    );
    expect(
      svc.findBestMatchDetailed('What are the two products of photosynthesis?')?.lesson.title,
      'Nutrition in Green Plants',
    );
    expect(
      svc.findBestMatchDetailed('Convert 1010₂ to base 10.')?.lesson.title,
      'Number Bases',
    );
    expect(
      svc.findBestMatchDetailed('Convert 1010 binary to denary')?.lesson.title,
      'Number Bases',
    );
    expect(
      svc.findBestMatchDetailed(
        'Which branch of physics studies forces and motion?',
      )?.subjectName,
      'Physics',
    );
    expect(
      svc.findBestMatchDetailed('Convert 5000g to kilograms.'),
      isNull,
      reason: 'unit conversion is school-math, not a lesson dump',
    );
    expect(
      svc.findBestMatchDetailed('Solve 2x + 3 = 11')?.lesson.title,
      isNot('Inequalities and Regions'),
    );
    expect(solveSchoolMath('What is 45% of 200?')?.answer, contains('90'));
    expect(solveSchoolMath('What is 3/4 of 80?')?.answer, contains('60'));
    expect(solveSchoolMath('Solve 2x + 3 = 11')?.answer, contains('4'));
    expect(solveSchoolMath('Convert 5000g to kilograms.')?.answer, contains('5'));
  });

  test('programming tutor notes include example and practice', () async {
    final svc = CurriculumService();
    await svc.loadAll();
    final match = svc.findBestMatchDetailed('Variables and Data Types');
    expect(match, isNotNull);
    expect(match!.lesson.title, 'Variables and Data Types');
    final notes = svc.buildProgrammingTutorNotes(match);
    expect(notes, contains('CHAT:'));
    expect(notes, contains('Example:'));
    expect(notes, contains('Practice:'));
  });

  test('coding chat opener still matches the named lesson', () async {
    final svc = CurriculumService();
    await svc.loadAll();
    expect(
      svc.findBestMatchDetailed(codingLessonChatOpener('Loops'))?.lesson.title,
      'Loops',
    );
    expect(
      svc
          .findBestMatchDetailed(
            codingLessonChatOpener('What is HTML and Web Pages'),
          )
          ?.lesson
          .title,
      'What is HTML and Web Pages',
    );
  });
}
