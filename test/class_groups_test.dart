import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/db/daos/class_group_dao.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/teacher/class_providers.dart';
import 'package:ai_connect_africa/features/teacher/teacher_dashboard_screen.dart';

void main() {
  late OticDatabase db;

  setUp(() {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() => db.close());

  Future<int> learner(String name, {int? classId}) =>
      db.into(db.students).insert(StudentsCompanion.insert(
            name: name,
            classGroupId: Value(classId),
          ));

  Future<void> progress(int studentId, String topic, int level, int sessions) =>
      db.into(db.topicProgress).insert(TopicProgressCompanion.insert(
            studentId: studentId,
            topic: topic,
            level: Value(level),
            sessionsCount: Value(sessions),
          ));

  group('ClassGroupDao', () {
    test('streams are labelled with their class', () async {
      final dao = db.classGroupDao;
      await dao.createClass(className: 'S2', streamName: 'East');
      await dao.createClass(className: 'S2', streamName: '  ');
      final classes = await dao.watchAllClasses().first;
      expect(classes.map(classLabel), ['S2', 'S2 East']);
    });

    test('deleting a class keeps its learners and their progress', () async {
      final dao = db.classGroupDao;
      final s2 = await dao.createClass(className: 'S2');
      final amina = await learner('Amina', classId: s2);
      await progress(amina, 'Cells', 40, 2);

      await dao.deleteClass(s2);

      final row = await db.studentDao.getStudentById(amina);
      expect(row, isNotNull);
      expect(row!.classGroupId, isNull,
          reason: 'FK is not enforced, so the DAO must clear it explicitly');
      expect(await db.sessionDao.getTopicProgress(amina), hasLength(1));
    });

    test('learners can be moved between classes and out of any class',
        () async {
      final dao = db.classGroupDao;
      final east = await dao.createClass(className: 'S2', streamName: 'East');
      final west = await dao.createClass(className: 'S2', streamName: 'West');
      final brian = await learner('Brian', classId: east);

      await dao.assignLearner(brian, west);
      expect((await db.studentDao.getStudentById(brian))!.classGroupId, west);
      await dao.assignLearner(brian, null);
      expect((await db.studentDao.getStudentById(brian))!.classGroupId, isNull);
    });

    test('learner stats are aggregated from topic progress', () async {
      final amina = await learner('Amina');
      final brian = await learner('Brian');
      await progress(amina, 'Cells', 40, 2);
      await progress(amina, 'Acids', 80, 3);

      final stats = await db.classGroupDao.watchLearnerStats().first;
      expect(stats[amina]!.topics, 2);
      expect(stats[amina]!.averageLevel, 60);
      expect(stats[amina]!.sessions, 5);
      expect(stats[brian]!.topics, 0,
          reason: 'a learner with no progress still gets a row');
      expect(stats[brian]!.averageLevel, 0);
    });
  });

  group('needs-attention rules', () {
    final now = DateTime(2026, 9, 23);
    Student row({required DateTime lastActive}) => Student(
          id: 1,
          name: 'A',
          language: 'en',
          interestsJson: '[]',
          learningStyle: 'unknown',
          strengthsJson: '[]',
          weaknessesJson: '[]',
          goalsJson: '[]',
          streakDays: 0,
          totalPoints: 0,
          createdAt: now,
          lastActiveAt: lastActive,
        );

    test('not started, inactive, low mastery, or fine', () {
      expect(needsHelpReason(row(lastActive: now), LearnerStats.empty, now),
          'Not started');
      expect(
        needsHelpReason(
          row(lastActive: now.subtract(const Duration(days: 9))),
          const LearnerStats(topics: 2, averageLevel: 70, sessions: 4),
          now,
        ),
        'Inactive 9 days',
      );
      expect(
        needsHelpReason(
          row(lastActive: now),
          const LearnerStats(topics: 2, averageLevel: 10, sessions: 4),
          now,
        ),
        'Low mastery',
      );
      expect(
        needsHelpReason(
          row(lastActive: now),
          const LearnerStats(topics: 2, averageLevel: 70, sessions: 4),
          now,
        ),
        isNull,
      );
    });
  });

  testWidgets('dashboard filters by class and shows class progress',
      (tester) async {
    late int east;
    await tester.runAsync(() async {
      east = await db.classGroupDao
          .createClass(className: 'S2', streamName: 'East');
      final amina = await learner('Amina', classId: east);
      await learner('Brian');
      await progress(amina, 'Cells', 60, 3);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TeacherDashboardScreen()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Amina'), findsOneWidget);
    expect(find.text('Brian'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'S2 East'));
    await tester.pump();

    expect(find.text('Amina'), findsOneWidget);
    expect(find.text('Brian'), findsNothing);
    expect(find.text('60%'), findsWidgets,
        reason: 'class average and the learner bar both show 60%');
    expect(find.text('Delete class'), findsOneWidget);
    expect(find.text('Subjects & materials'), findsOneWidget);

    // Dispose the tree, then let drift's stream-cleanup timer fire on the
    // fake clock — otherwise the test fails on a pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
