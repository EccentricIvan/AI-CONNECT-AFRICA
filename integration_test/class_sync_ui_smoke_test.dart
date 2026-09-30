import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_connect_africa/collaboration/sync/class_share_server.dart';
import 'package:ai_connect_africa/collaboration/sync/selective_sync_manager.dart';
import 'package:ai_connect_africa/core/theme/app_theme.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/collaborate/class_sync_screen.dart';
import 'package:ai_connect_africa/features/teacher/teacher_device_screens.dart';
import 'package:ai_connect_africa/features/teacher/teacher_sync_screen.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Class sync screens on the real Windows build, sharing for real over
/// localhost — in-memory databases and mocked preferences, so the device's
/// own data is never touched. Fails on any exception or layout overflow.
/// Set OTIC_E2E_OUT to a folder to keep screenshots.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  OticDatabase memDb() =>
      OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));

  final shot = GlobalKey();
  final outDir = Platform.environment['OTIC_E2E_OUT'];

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (outDir == null) return;
    await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$outDir/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Future<void> show(WidgetTester tester, OticDatabase db, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: RepaintBoundary(
          key: shot,
          child: MaterialApp(theme: AppTheme.light, home: screen),
        ),
      ),
    );
  }

  /// Pumps until [finder] shows, doing real async work in between.
  Future<void> until(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  for (final (label, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1280, 860)),
  ]) {
    testWidgets('Class sync screens render and share ($label)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late OticDatabase teacher, student;
      late ClassGroup east;
      late ClassShareServer server;
      late int studentId;
      await tester.runAsync(() async {
        // Teacher device: school, class, a shared note, sharing on.
        teacher = memDb();
        await teacher.classSyncDao.setSchoolName('Bright Future Academy');
        final id = await teacher.classGroupDao.createClass(
          className: 'S2',
          streamName: 'East',
        );
        east = await (teacher.select(
          teacher.classGroups,
        )..where((t) => t.id.equals(id))).getSingle();
        await OfflineStorageService(teacher).insertTopicResource(
          subjectId: 'chemistry',
          topicKey: 'acids',
          resourceTitle: 'Acids notes',
          content: 'Acids turn blue litmus red.',
        );
        await teacher.classSyncDao.setShares(
          subjectId: 'chemistry',
          documentTitle: 'Acids notes',
          classUuids: {east.groupUuid!},
        );
        server = ClassShareServer(teacher, joinRounds: 1000);
        server.pendingJoinsStream.listen((p) {
          for (final j in p) {
            server.decide(j.id, accept: true);
          }
        });
        final port = await server.start(classUuids: {east.groupUuid!}, port: 0);

        // Student device: joins, gets progress, syncs.
        student = memDb();
        studentId = await student
            .into(student.students)
            .insert(StudentsCompanion.insert(name: 'Amina'));
        await student
            .into(student.topicProgress)
            .insert(
              TopicProgressCompanion.insert(
                studentId: studentId,
                topic: 'Acids',
                level: const Value(35),
              ),
            );
        SharedPreferences.setMockInitialValues({kActiveStudentIdKey: studentId});
        final m = SelectiveSyncManager(student, joinRounds: 1000);
        final code = await server.openJoinCode(east);
        final at = (address: '127.0.0.1', port: port);
        final joined = await m.joinClass(
          teachers: [at],
          typedCode: code!,
          name: 'Amina',
        );
        await student.classGroupDao.assignLearner(studentId, joined.group!.id);
        final r = await m.syncClass(teacher: at, group: joined.group!);
        expect(r.ok, isTrue, reason: r.error);
        expect(r.learnersReported, 1);
        m.dispose();
        await server.stop();
      });

      // ── Student: Class sync, then Share with classmates ──────────────
      await show(tester, student, const ClassSyncScreen());
      await until(tester, find.text('Share with classmates'));
      await until(tester, find.text('My subjects'));
      await screenshot(tester, 'student_top_$label');
      await tester.scrollUntilVisible(
        find.text('Start sharing'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Start sharing'));
      await until(tester, find.text('Stop sharing'));
      await until(tester, find.text('Nobody is waiting to join'));
      await screenshot(tester, 'student_class_sync_$label');
      expect(tester.takeException(), isNull);

      // ── Teacher: Class sync, sharing, with a join waiting ───────────
      await show(tester, teacher, const TeacherSyncScreen());
      await until(tester, find.text('Start sharing this class'));
      await tester.tap(find.text('Start sharing this class'));
      await until(tester, find.text('Stop sharing'));
      await until(tester, find.textContaining('Class progress'));
      expect(find.text('Amina'), findsWidgets, reason: 'progress reported');
      await screenshot(tester, 'teacher_class_sync_$label');
      expect(tester.takeException(), isNull);

      // ── The teacher-role screens ─────────────────────────────────────
      await show(
        tester,
        student,
        const TeacherDeviceSetupScreen(destination: '/teacher'),
      );
      await until(tester, find.text('Yes, this is the teacher’s device'));
      await screenshot(tester, 'teacher_setup_$label');
      await show(tester, student, const StudentDeviceScreen());
      await until(tester, find.text('Open Class sync'));
      await screenshot(tester, 'student_device_$label');
      expect(tester.takeException(), isNull);

      // Leave the screens so their servers and sockets stop.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await teacher.close();
        await student.close();
      });
    });
  }
}
