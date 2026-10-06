import 'dart:convert';
import 'dart:io';

import 'package:ai_connect_africa/collaboration/admin/admin_records.dart';
import 'package:ai_connect_africa/collaboration/admin/admin_records_crypto.dart';
import 'package:ai_connect_africa/collaboration/admin/admin_records_share.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/admin/admin_service.dart';
import 'package:ai_connect_africa/features/teacher/teacher_profiles.dart';
import 'package:ai_connect_africa/memory/session_recall_store.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/learner_data_wiper.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/projects/project_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rounds = 1000;

void main() {
  late OticDatabase adminDb;
  late AdminService admin;
  late AdminSession session;
  final others = <OticDatabase>[];

  OticDatabase device() {
    final db = OticDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory()),
    );
    others.add(db);
    return db;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adminDb = device();
    final tmp = await Directory.systemTemp.createTemp('admin_sync');
    admin = AdminService(
      adminDb,
      CustomSubjectService(adminDb, OfflineStorageService(adminDb)),
      LearnerDataWiper(
        adminDb,
        recallStore: SessionRecallStore(directory: tmp),
        certificatesDir: () async => tmp,
        projectStore: ProjectStore(root: () async => tmp),
      ),
    );
    session = (await admin.setUp(name: 'Head', pin: '2468'))!;
    await adminDb.classSyncDao.setSchoolName('Bright Future Academy');
    await admin.addTeacher(session, name: 'Amina', pin: '1234');
    await admin.addClass(session, className: 'S3', streamName: 'East');
    await admin.addSubject(session, 'Maths 9');
    final teacher = (await TeacherProfileService(adminDb).all()).single;
    final east = (await adminDb.select(adminDb.classGroups).get()).single;
    await admin.assign(
      session,
      teacherId: teacher.id,
      classGroupUuid: east.groupUuid!,
      subjectId: 'maths_9',
      academicYear: 2026,
    );
    final learner = (await admin.addLearner(session, name: 'Babirye'))!;
    await admin.enrol(
      session,
      studentId: learner,
      group: east,
      academicYear: 2026,
    );
  });

  tearDown(() async {
    for (final db in others) {
      await db.close();
    }
    others.clear();
  });

  group('signed records', () {
    test('a device receives every school record, ready to sign in', () async {
      final target = device();
      final bundle = await AdminRecords(adminDb).export();
      expect(await AdminRecords(target).apply(bundle), isNull);

      final teacher = (await TeacherProfileService(target).all()).single;
      expect(teacher.name, 'Amina');
      expect(
        await TeacherProfileService(target).signIn(teacher.id, '1234'),
        isNotNull,
        reason: 'teachers sign in on any device the records reached',
      );
      final classes = await target.select(target.classGroups).get();
      expect(classes.single.className, 'S3');
      expect(classes.single.classKey, isNotNull);
      expect(classes.single.joined, isFalse);
      expect(
        (await target.select(target.teachingAssignments).get()).single.teacherId,
        teacher.id,
      );
      final learner = (await target.select(target.students).get()).single;
      expect(learner.name, 'Babirye');
      expect(learner.classGroupId, classes.single.id);
      expect((await target.classSyncDao.identity()).schoolName,
          'Bright Future Academy');
      expect((await AdminRecords(target).received())!.version, 1);
    });

    test('a tampered bundle is refused', () async {
      final target = device();
      final bundle = await AdminRecords(adminDb).export();
      final tampered = {
        ...bundle!,
        'payload': (bundle['payload']! as String).replaceAll('Amina', 'Mallory'),
      };
      expect(await AdminRecords(target).apply(tampered), isNotNull);
      expect(await target.select(target.teacherProfiles).get(), isEmpty);
    });

    test('records from another Admin are refused once one is trusted',
        () async {
      final target = device();
      expect(
        await AdminRecords(target).apply(await AdminRecords(adminDb).export()),
        isNull,
      );
      // Another device sets itself up as an Admin of the same school.
      final rogue = device();
      await AdminService(
        rogue,
        CustomSubjectService(rogue, OfflineStorageService(rogue)),
        LearnerDataWiper(rogue),
      ).setUp(name: 'Rogue', pin: '1111');
      final me = await target.classSyncDao.identity();
      await rogue.classSyncDao.adoptSchool(
        schoolId: me.schoolId!,
        schoolName: 'Bright Future Academy',
      );
      final forged = await AdminRecords(rogue).export();
      expect(await AdminRecords(target).apply(forged), isNotNull);
    });

    test('an old or replayed bundle never rolls a device back', () async {
      final target = device();
      final first = await AdminRecords(adminDb).export();
      expect(await AdminRecords(target).apply(first), isNull);
      expect(
        await AdminRecords(target).apply(first),
        isNotNull,
        reason: 'the same bundle again',
      );
      await admin.addTeacher(session, name: 'Okello', pin: '9876');
      final second = await AdminRecords(adminDb).export();
      expect(await AdminRecords(target).apply(second), isNull);
      expect(await AdminRecords(target).apply(first), isNotNull);
      expect((await target.select(target.teacherProfiles).get()).length, 2);
    });

    test('a device of another school refuses the records', () async {
      final target = device();
      await target.classSyncDao.setSchoolName('Other School');
      expect(
        await AdminRecords(target).apply(await AdminRecords(adminDb).export()),
        isNotNull,
      );
    });

    test('the Admin’s own device never takes records', () async {
      expect(
        await AdminRecords(adminDb).apply(await AdminRecords(adminDb).export()),
        isNotNull,
      );
    });

    test('teacher and learner PIN hashes travel only inside the signed '
        'records; the Admin’s details only sealed', () async {
      final details = (await AdminRecords(adminDb).takeoverDetails())!;
      final sealed = await sealAdminTakeover(
        passphrase: 'correct horse battery',
        admin: details,
        rounds: _rounds,
      );
      final bundle = await AdminRecords(adminDb).export(takeover: sealed);
      expect(bundle!['payload'] as String, isNot(contains(details['seed'] as String)));
    });
  });

  group('taking over as Admin', () {
    test('needs the passphrase, then signs in with the Admin PIN', () async {
      final target = device();
      final details = (await AdminRecords(adminDb).takeoverDetails())!;
      final sealed = await sealAdminTakeover(
        passphrase: 'correct horse battery',
        admin: details,
        rounds: _rounds,
      );
      await AdminRecords(target).apply(
        await AdminRecords(adminDb).export(takeover: sealed),
      );
      final targetAdmin = AdminService(
        target,
        CustomSubjectService(target, OfflineStorageService(target)),
        LearnerDataWiper(target),
      );
      expect(
        await targetAdmin.setUp(name: 'Second', pin: '3333'),
        isNull,
        reason: 'one Admin per school',
      );
      expect(await AdminRecords(target).takeOver('wrong passphrase!'), isFalse);
      expect(await AdminRecords(target).takeOver('correct horse battery'), isTrue);
      expect(await targetAdmin.signIn('2468'), isNotNull);

      // Its next records outrank the ones it received.
      final next = jsonDecode(
        (await AdminRecords(target).export())!['payload'] as String,
      );
      expect(next['version'], 2);
    });
  });

  group('sending over the network', () {
    late AdminRecordsServer server;
    late int port;

    setUp(() async {
      server = AdminRecordsServer(
        adminDb,
        approvalTimeout: const Duration(seconds: 5),
        kdfRounds: _rounds,
      );
      port = await server.start();
    });
    tearDown(() => server.stop());

    Future<String?> receive(OticDatabase target, String code) =>
        receiveAdminRecords(
          target,
          address: '127.0.0.1',
          port: port,
          typedCode: code,
          deviceName: 'Lab PC',
          kdfRounds: _rounds,
        );

    test('a wrong code gets nothing', () async {
      final target = device();
      expect(await receive(target, 'ABCD-EFGH'), isNotNull);
      expect(await target.select(target.teacherProfiles).get(), isEmpty);
    });

    test('nothing is sent until the Admin accepts', () async {
      final target = device();
      server.pending.listen((p) {
        for (final r in p) {
          expect(r.name, 'Lab PC');
          server.decide(r, accept: false);
        }
      });
      expect(await receive(target, server.code!), isNotNull);
      expect(await target.select(target.teacherProfiles).get(), isEmpty);
    });

    test('accepted, the records arrive and apply', () async {
      final target = device();
      server.pending.listen((p) {
        for (final r in p) {
          server.decide(r, accept: true);
        }
      });
      expect(await receive(target, server.code!), isNull);
      expect(
        (await target.select(target.teacherProfiles).get()).single.name,
        'Amina',
      );
    });
  });
}
