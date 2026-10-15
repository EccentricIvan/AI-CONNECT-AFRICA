import 'dart:io';

import 'package:ai_connect_africa/collaboration/admin/admin_records.dart';
import 'package:ai_connect_africa/collaboration/sync/class_share_server.dart';
import 'package:ai_connect_africa/collaboration/sync/selective_sync_manager.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/admin/admin_service.dart';
import 'package:ai_connect_africa/features/teacher/teacher_profiles.dart';
import 'package:ai_connect_africa/memory/session_recall_store.dart';
import 'package:ai_connect_africa/services/assignments/class_assignments.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/learner_data_wiper.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/projects/project_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rounds = 1000;

/// A whole school, role by role, across three devices: the Admin's PC, a
/// teacher's phone and a learner's laptop. Records travel from the Admin to
/// both devices first (as in a real school), then class sync runs on top of
/// them: notes, an assignment, the answer and the grade.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final dbs = <OticDatabase>[];
  OticDatabase device() {
    final db = OticDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory()),
    );
    dbs.add(db);
    return db;
  }

  tearDown(() async {
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
  });

  test('Admin records, then class sync, then assignment and grade', () async {
    SharedPreferences.setMockInitialValues({});

    // ── Admin's PC ───────────────────────────────────────────────────────
    final adminDb = device();
    final tmp = await Directory.systemTemp.createTemp('school_e2e');
    addTearDown(() => tmp.delete(recursive: true));
    final admin = AdminService(
      adminDb,
      CustomSubjectService(adminDb),
      LearnerDataWiper(
        adminDb,
        recallStore: SessionRecallStore(directory: tmp),
        certificatesDir: () async => tmp,
        projectStore: ProjectStore(root: () async => tmp),
      ),
    );
    final session = (await admin.setUp(name: 'Head', pin: '2468'))!;
    await adminDb.classSyncDao.setSchoolName('Bright Future Academy');
    await admin.addTeacher(session, name: 'Amina', pin: '1234');
    await admin.addClass(session, className: 'S3', streamName: 'East');
    await admin.addSubject(session, 'Maths 9');
    final aminaId =
        (await TeacherProfileService(adminDb).all()).single.id;
    final eastOnAdmin =
        (await adminDb.select(adminDb.classGroups).get()).single;
    await admin.assign(
      session,
      teacherId: aminaId,
      classGroupUuid: eastOnAdmin.groupUuid!,
      subjectId: 'maths_9',
      academicYear: 2026,
    );
    final babirye = (await admin.addLearner(session, name: 'Babirye'))!;
    await admin.enrol(
      session,
      studentId: babirye,
      group: eastOnAdmin,
      academicYear: 2026,
    );
    final records = await AdminRecords(adminDb).export();

    // ── The records reach the teacher's phone and the learner's laptop ──
    final teacherDb = device();
    final learnerDb = device();
    expect(await AdminRecords(teacherDb).apply(records), isNull);
    expect(await AdminRecords(learnerDb).apply(records), isNull);

    // The teacher signs in with the PIN the Admin gave, on the new device.
    final signedIn = await TeacherProfileService(teacherDb).signIn(
      (await TeacherProfileService(teacherDb).all()).single.id,
      '1234',
    );
    expect(signedIn, isNotNull);

    // ── Teacher uploads a note + assignment and shares them ──────────────
    final east = (await teacherDb.select(teacherDb.classGroups).get()).single;
    await OfflineStorageService(teacherDb).insertTopicResource(
      subjectId: 'maths_9',
      topicKey: 'fractions',
      resourceTitle: 'Fractions notes',
      content: 'A fraction is a part of a whole.',
    );
    final assignments = ClassAssignments(teacherDb);
    final title = (await assignments.create(
      subjectId: 'maths_9',
      title: 'Fractions',
      instructions: 'Add 1/2 and 1/4.',
      maxPoints: 5,
    ))!;
    for (final t in ['Fractions notes', title]) {
      await teacherDb.classSyncDao.setShares(
        subjectId: 'maths_9',
        documentTitle: t,
        classUuids: {east.groupUuid!},
      );
    }
    final server = ClassShareServer(teacherDb, joinRounds: _rounds);
    addTearDown(server.stop);
    server.pendingJoinsStream.listen((pending) {
      for (final p in pending) {
        server.decide(p.id, accept: true);
      }
    });
    final port = await server.start(classUuids: {east.groupUuid!}, port: 0);
    final endpoint = (address: '127.0.0.1', port: port);

    // ── Learner's laptop joins with the teacher's code ───────────────────
    final manager = SelectiveSyncManager(learnerDb, joinRounds: _rounds);
    addTearDown(manager.dispose);
    final code = await server.openJoinCode(east);
    final joined = await manager.joinClass(
      teachers: [endpoint],
      typedCode: code!,
    );
    expect(
      joined.error,
      isNull,
      reason: 'a device that already holds the Admin’s records must still '
          'be able to join its class through the teacher',
    );
    final group = joined.group!;
    expect(group.groupUuid, east.groupUuid);
    expect((await learnerDb.select(learnerDb.classGroups).get()).length, 1,
        reason: 'one class row, not a duplicate');

    final result = await manager.syncClass(teacher: endpoint, group: group);
    expect(result.ok, isTrue, reason: result.error);

    // ── Learner sees the note and the assignment, and answers ────────────
    final learnerSide = ClassAssignments(learnerDb);
    final seen = await learnerSide.visible(group.groupUuid);
    expect(seen.single.title, 'Fractions');
    final learner = (await learnerDb.select(learnerDb.students).get())
        .firstWhere((s) => s.name == 'Babirye');
    expect(await learnerSide.submit(
      student: learner,
      assignment: seen.single,
      answer: '3/4',
      memberKey: 'local/${learner.id}',
    ), isTrue);
    await manager.syncClass(teacher: endpoint, group: group);

    // ── Teacher grades; the grade returns to that learner ────────────────
    final answers = await teacherDb.select(teacherDb.assignmentSubmissions).get();
    expect(answers.single.answer, '3/4');
    await assignments.grade(answers.single.uuid, 5, 'Correct');
    await manager.syncClass(teacher: endpoint, group: group);
    final mine = await learnerDb.select(learnerDb.assignmentSubmissions).get();
    expect(mine.single.grade, 5);
    expect(mine.single.feedback, 'Correct');

    // ── The Admin adds a learner; the next records keep everyone enrolled ─
    final extra = (await admin.addLearner(session, name: 'Kato'))!;
    await admin.enrol(
      session,
      studentId: extra,
      group: eastOnAdmin,
      academicYear: 2026,
    );
    expect(
      await AdminRecords(learnerDb).apply(await AdminRecords(adminDb).export()),
      isNull,
    );
    final students = await learnerDb.select(learnerDb.students).get();
    expect(students.map((s) => s.name), containsAll(['Babirye', 'Kato']));
    for (final s in students) {
      expect(s.classGroupId, group.id,
          reason: '${s.name} stays in the class the device joined');
    }
  });
}
