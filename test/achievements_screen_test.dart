import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/achievements/achievements_screen.dart';
import 'package:ai_connect_africa/l10n/app_locale.dart';

/// The complaint this answers: Achievements showing numbers that don't move
/// with what the student actually did. Seeding real counters in a real
/// (in-memory) database and asserting the screen prints them back — at a
/// phone width, so a layout overflow fails this test too — is the only way
/// to prove that, versus reading the widget source and assuming it's wired.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Achievements shows live per-area progress at phone width, not '
      'hardcoded placeholders', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    await db.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina', language: const Value('en')),
    );
    await db.studentDao.updateStudent(const StudentsCompanion(
      id: Value(1),
      totalPracticeAttempted: Value(5),
      totalPracticeCorrect: Value(3),
      totalScenariosCompleted: Value(2),
    ));

    final container =
        ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppLocale(languageCode: 'en', child: AchievementsScreen()),
        ),
      ),
    );

    // Not pumpAndSettle: the loading spinner never settles on its own.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull,
        reason: 'a layout overflow or other render error at phone width');
    expect(find.text('3/5 correct'), findsOneWidget);
    expect(find.text('2 scenarios completed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a First Step badge earned with no lesson tracker data floors the '
      'Learn card at 1, instead of "Completed" next to "0 lessons done"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    await db.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina', language: const Value('en')),
    );
    // Earned before the lifetime counters existed to back it — both
    // trackers genuinely read 0 for this student.
    await db.badgeDao.awardBadge(
      studentId: 1,
      badgeId: 'first_lesson',
      badgeName: 'First Step',
    );

    final container =
        ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppLocale(languageCode: 'en', child: AchievementsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('0 lessons done'), findsNothing);
    expect(find.text('1 lesson done'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
