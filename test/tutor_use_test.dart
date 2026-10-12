import 'dart:io';

import 'package:ai_connect_africa/collaboration/sync/progress_report.dart';
import 'package:ai_connect_africa/curriculum/curriculum_models.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/learn/notes_quiz.dart';
import 'package:ai_connect_africa/services/learning/tutor_use.dart';
import 'package:ai_connect_africa/services/notes/quiz_scores.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _q = QuizQuestion(
  question: 'What gas do plants take in?',
  options: ['Carbon dioxide', 'Oxygen', 'Nitrogen', 'Helium'],
  correct: 0,
  explanation: '',
);

ProgressReport _report({List<Object?>? quizzes}) => ProgressReport.fromJson({
  'member': 'dev/1',
  'name': 'Amina',
  'quizzes': ?quizzes,
})!;

void main() {
  group('quiz answers after a tutor reply', () {
    late ProviderContainer container;
    late SubjectQuizNotifier quiz;
    final shown = DateTime(2026, 10, 12, 9);

    setUp(() {
      // A finished round is saved for the active learner; there is none.
      container = ProviderContainer(
        overrides: [
          activeStudentProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      quiz = container.read(subjectQuizProvider('biology').notifier);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      quiz.state = SubjectQuizState(
        questions: const [_q, _q, _q],
        topics: const ['Cells', 'Cells', 'Leaves'],
        target: 3,
        shownAt: [shown, shown, shown],
      );
    });

    SubjectQuizState state() => container.read(subjectQuizProvider('biology'));

    test('are marked only when the reply came after the question appeared',
        () {
      container.read(tutorLastReplyProvider.notifier).state =
          shown.subtract(const Duration(minutes: 1));
      quiz.answer(0, 0);
      expect(state().tutorUsed, isEmpty, reason: 'reply came before');

      container.read(tutorLastReplyProvider.notifier).state =
          shown.add(const Duration(minutes: 2));
      quiz.answer(1, 1);
      expect(state().tutorUsed, {1});
    });

    test('with no reply at all, nothing is marked', () {
      quiz.answer(0, 0);
      quiz.answer(2, 0);
      expect(state().tutorUsed, isEmpty);
    });

    test('tally per topic counts them', () {
      container.read(tutorLastReplyProvider.notifier).state =
          shown.add(const Duration(minutes: 2));
      quiz.answer(0, 0);
      quiz.answer(1, 1);
      container.read(tutorLastReplyProvider.notifier).state = null;
      quiz.answer(2, 0);
      expect(state().scoreByTopic, {
        'Cells': (1, 2, 2),
        'Leaves': (1, 1, 0),
      });
    });
  });

  test('a round saved before schema 31 reads as unknown, not none', () async {
    final db = OticDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO quiz_results (student_id, subject_id, topic, correct, total, "
      "taken_at) VALUES (1, 'biology', 'Cells', 3, 5, '2026-10-01')",
    );
    final s = (await QuizScores(db).watch(1).first).single;
    expect(s.lastTutorUsed, isNull);
  });

  test('a v30 database with quiz results upgrades to v31 and keeps them',
      () async {
    final dir = await Directory.systemTemp.createTemp('otic_migration_test');
    final file = File(p.join(dir.path, 'test.sqlite'));
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final seed = OticDatabase.forTesting(NativeDatabase(file));
    await seed.customStatement(
      "INSERT INTO quiz_results (student_id, subject_id, topic, correct, total, "
      "taken_at) VALUES (1, 'biology', 'Cells', 3, 5, '2026-10-01')",
    );
    await seed.customStatement(
      'ALTER TABLE quiz_results DROP COLUMN tutor_used',
    );
    await seed.customStatement('PRAGMA user_version = 30');
    await seed.close();

    for (var run = 0; run < 2; run++) {
      final db = OticDatabase.forTesting(NativeDatabase(file));
      final s = (await QuizScores(db).watch(1).first).single;
      expect((s.lastCorrect, s.lastTotal), (3, 5));
      expect(s.lastTutorUsed, isNull);
      await db.customStatement('PRAGMA user_version = 30');
      await db.close();
    }
  });

  group('progress report quizzes', () {
    test('round-trip, counts only', () {
      final r = _report(
        quizzes: [
          {'s': 'biology', 't': 'Cells', 'c': 4, 'n': 5, 'a': 2},
          {'s': 'biology', 't': 'Leaves', 'c': 1, 'n': 2},
        ],
      );
      expect(r.quizzes, hasLength(2));
      expect(r.quizzes.first.tutorUsed, 2);
      expect(r.quizzes.last.tutorUsed, isNull);
      final back = ProgressReport.fromJson(r.toJson())!;
      expect(back.quizzes.map((q) => (q.topic, q.correct, q.total, q.tutorUsed)),
          [('Cells', 4, 5, 2), ('Leaves', 1, 2, null)]);
    });

    test('a report without quizzes has no quizzes key, so its digest is '
        'unchanged', () {
      expect(_report().toJson().containsKey('quizzes'), isFalse);
    });

    test('bad entries are dropped and counts clamped', () {
      final r = _report(
        quizzes: [
          {'s': 'biology', 't': 'Cells', 'c': 9, 'n': 5, 'a': 7},
          {'s': 'biology', 't': 'Zero', 'c': 0, 'n': 0},
          {'s': 'biology', 't': 'Huge', 'c': 1, 'n': 100000},
          'junk',
        ],
      );
      expect(r.quizzes, hasLength(1));
      expect((r.quizzes.single.correct, r.quizzes.single.tutorUsed), (5, 5));
    });
  });

  test('tutorUsedSince', () {
    final t = DateTime(2026, 10, 12);
    expect(tutorUsedSince(null, t), isFalse);
    expect(tutorUsedSince(t, t), isFalse);
    expect(tutorUsedSince(t.add(const Duration(seconds: 1)), t), isTrue);
  });
}
