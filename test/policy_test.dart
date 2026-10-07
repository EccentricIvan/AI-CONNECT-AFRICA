import 'dart:io';

import 'package:ai_connect_africa/core/policy/policy.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/admin/admin_service.dart';
import 'package:ai_connect_africa/features/teacher/teacher_profiles.dart';
import 'package:ai_connect_africa/features/teacher/teaching_scope.dart';
import 'package:ai_connect_africa/memory/session_recall_store.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/learner_data_wiper.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/projects/project_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [Policy] must answer exactly as the checks it stands in front of.
void main() {
  late OticDatabase db;
  late AdminService admin;
  late AdminSession s;
  late int amina, okello, learner;
  late ClassGroup east, west;
  var gated = true;
  late Policy policy;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    final tmp = await Directory.systemTemp.createTemp('policy_test');
    admin = AdminService(
      db,
      CustomSubjectService(db, OfflineStorageService(db)),
      LearnerDataWiper(
        db,
        recallStore: SessionRecallStore(directory: tmp),
        certificatesDir: () async => tmp,
        projectStore: ProjectStore(root: () async => tmp),
      ),
    );
    gated = true;
    policy = Policy(db, gated: () async => gated);

    s = (await admin.setUp(name: 'Head', pin: '2468'))!;
    await admin.addTeacher(s, name: 'Amina', pin: '1234');
    await admin.addTeacher(s, name: 'Okello', pin: '9876');
    final teachers = await TeacherProfileService(db).all();
    amina = teachers.firstWhere((t) => t.name == 'Amina').id;
    okello = teachers.firstWhere((t) => t.name == 'Okello').id;
    await admin.addClass(s, className: 'S3', streamName: 'East');
    await admin.addClass(s, className: 'S4', streamName: 'West');
    final classes = await db.select(db.classGroups).get();
    east = classes.firstWhere((c) => c.className == 'S3');
    west = classes.firstWhere((c) => c.className == 'S4');
    await admin.addSubject(s, 'Maths 9');
    await admin.addSubject(s, 'Physics 9');
    for (final (t, c, subj) in [
      (amina, east, 'maths_9'),
      (okello, east, 'physics_9'),
    ]) {
      await admin.assign(
        s,
        teacherId: t,
        classGroupUuid: c.groupUuid!,
        subjectId: subj,
        academicYear: 2026,
      );
    }
    learner = (await admin.addLearner(s, name: 'Babirye'))!;
    await admin.enrol(s, studentId: learner, group: east, academicYear: 2026);
    await TeachingScope(db).recordOwner('maths_9', 'Algebra', amina);
  });
  tearDown(() => db.close());

  test('teacher actions follow TeachingScope exactly', () async {
    final scope = TeachingScope(db);
    for (final teacher in [amina, okello, null]) {
      final actor = TeacherActor(teacher);
      for (final subject in ['maths_9', 'physics_9']) {
        expect(
          await policy.can(actor, UploadNote(subject)),
          await scope.teaches(teacher, subject),
        );
        expect(
          await policy.can(actor, ChangeNote(subject, 'Algebra')),
          await scope.mayChangeNote(teacher, subject, 'Algebra'),
        );
        for (final c in [east, west]) {
          expect(
            await policy.can(
              actor,
              ShareNote(subject, 'Algebra', c.groupUuid!),
            ),
            await scope.mayShare(teacher, subject, 'Algebra', c.groupUuid!),
          );
        }
      }
    }
    expect(
      await policy.can(TeacherActor(amina), const UploadNote('maths_9')),
      isTrue,
    );
    expect(
      await policy.can(
        TeacherActor(okello),
        const ChangeNote('maths_9', 'Algebra'),
      ),
      isFalse,
    );
  });

  test(
    'only teachers change notes; only the Admin manages the school',
    () async {
      for (final actor in [
        AdminActor(s),
        LearnerActor(learner),
        const GuestActor(),
      ]) {
        expect(await policy.can(actor, const UploadNote('maths_9')), isFalse);
        expect(
          await policy.can(actor, const ChangeNote('maths_9', 'Algebra')),
          isFalse,
        );
      }
      expect(await policy.can(AdminActor(s), const ManageSchool()), isTrue);
      for (final actor in [
        TeacherActor(amina),
        LearnerActor(learner),
        const GuestActor(),
      ]) {
        expect(await policy.can(actor, const ManageSchool()), isFalse);
      }
    },
  );

  test('a learner reads only the subjects taught to their class', () async {
    expect(await policy.readableSubjects(LearnerActor(learner)), {
      'maths_9',
      'physics_9',
    });
    expect(
      await policy.can(LearnerActor(learner), const ReadNotes('maths_9')),
      isTrue,
    );
    await admin.enrol(s, studentId: learner, group: west, academicYear: 2026);
    expect(
      await policy.can(LearnerActor(learner), const ReadNotes('maths_9')),
      isFalse,
    );
    expect(await policy.readableSubjects(const GuestActor()), isEmpty);
    expect(await policy.readableSubjects(const TeacherActor(null)), isNull);
  });

  test('with no Teachers PIN nothing is gated', () async {
    gated = false;
    await admin.enrol(s, studentId: learner, group: west, academicYear: 2026);
    expect(await policy.readableSubjects(LearnerActor(learner)), isNull);
    expect(await policy.readableSubjects(const GuestActor()), isNull);
  });
}
