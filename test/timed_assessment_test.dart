import 'dart:io';

import 'package:ai_connect_africa/collaboration/cloud/cloud_sync.dart';
import 'package:ai_connect_africa/collaboration/sync/progress_report.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/services/assignments/class_assignments.dart';
import 'package:ai_connect_africa/services/notes/note_pdf_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeCloud extends CloudSyncAdapter {
  bool on = true;
  bool fail = false;
  final received = <String, CloudRecord>{};

  @override
  bool get enabled => on;

  @override
  Future<Set<String>> push(List<CloudRecord> records) async {
    if (fail) throw const SocketException('offline');
    for (final r in records) {
      received[r.id] = r;
    }
    return {for (final r in records) r.id};
  }
}

void main() {
  late OticDatabase db;
  late _FakeCloud cloud;
  late CloudOutboxService outbox;
  late ClassAssignments service;
  late Student amina;
  final nine = DateTime.utc(2026, 10, 12, 9);

  setUp(() async {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    cloud = _FakeCloud();
    outbox = CloudOutboxService(db, cloud);
    service = ClassAssignments(
      db,
      cloud: (kind, uuid, {recordId}) =>
          outbox.enqueue(kind, uuid, recordId: recordId),
    );
    final id = await db.studentDao.createStudent(
      StudentsCompanion.insert(name: 'Amina'),
    );
    amina = (await db.studentDao.getStudentById(id))!;
  });

  tearDown(() => db.close());

  Future<ClassAssignment> make({
    int? minutes = 30,
    DateTime? opens,
    DateTime? closes,
  }) async {
    await service.create(
      subjectId: 'biology',
      title: 'Cells',
      instructions: 'Q1. Name two organelles.',
      maxPoints: 10,
      kind: AssignmentKind.holiday,
      opensAt: opens,
      closesAt: closes,
      minutes: minutes,
    );
    return (await service.own()).single;
  }

  Future<List<AssignmentSubmission>> mine() =>
      service.watchMine(amina.id).first;

  test(
    'the assessment travels in its note with type, window and limit',
    () async {
      final a = await make(
        opens: nine,
        closes: nine.add(const Duration(days: 7)),
      );
      expect(a.kind, AssignmentKind.holiday);
      expect(a.documentTitle, 'Holiday assessment — Cells');
      expect((a.opensAt, a.minutes), (nine, 30));
      expect(a.timed, isTrue);
    },
  );

  test('an ordinary assignment reads exactly as before', () {
    const a = ClassAssignment(
      id: 'x',
      subjectId: 's',
      title: 't',
      instructions: '',
      maxPoints: 5,
    );
    expect(a.toJson().keys, ['id', 'title', 'instructions', 'max', 'due']);
    expect(a.timed, isFalse);
  });

  test('deadline: the time limit or closing time, whichever first', () {
    final a = ClassAssignment(
      id: 'x',
      subjectId: 's',
      title: 't',
      instructions: '',
      maxPoints: 5,
      minutes: 60,
      closesAt: nine.add(const Duration(minutes: 30)),
    );
    expect(a.deadlineFor(nine), nine.add(const Duration(minutes: 30)));
    expect(
      a.deadlineFor(nine.subtract(const Duration(hours: 2))),
      nine.subtract(const Duration(hours: 1)),
    );
  });

  test('cannot start before it opens or after it closes', () async {
    final a = await make(
      opens: nine,
      closes: nine.add(const Duration(hours: 2)),
    );
    expect(
      await service.start(
        amina.id,
        a,
        now: nine.subtract(const Duration(minutes: 1)),
      ),
      isNull,
    );
    expect(
      await service.start(amina.id, a, now: nine.add(const Duration(hours: 2))),
      isNull,
    );
    expect(await service.start(amina.id, a, now: nine), isNotNull);
  });

  test('starting twice keeps the first start time', () async {
    final a = await make();
    final first = await service.start(amina.id, a, now: nine);
    final again = await service.start(
      amina.id,
      a,
      now: nine.add(const Duration(minutes: 10)),
    );
    expect(again!.startedAt, first!.startedAt);
  });

  test('handed in once, with its start time; never again', () async {
    final a = await make();
    await service.start(amina.id, a, now: nine);
    expect(
      await service.submit(
        student: amina,
        assignment: a,
        answer: 'Nucleus, ribosome',
        memberKey: 'local/1',
        now: nine.add(const Duration(minutes: 12)),
      ),
      isTrue,
    );
    expect(
      await service.submit(
        student: amina,
        assignment: a,
        answer: 'second try',
        memberKey: 'local/1',
      ),
      isFalse,
    );
    final s = (await mine()).single;
    expect(s.startedAt, nine.toIso8601String());
    expect(await service.attempt(amina.id, a.id), isNull);
    expect(await service.start(amina.id, a), isNull, reason: 'handed in');
  });

  test('when time runs out the draft is handed in as it stands', () async {
    final a = await make(minutes: 30);
    await service.start(amina.id, a, now: nine);
    await service.saveDraft(amina.id, a.id, 'Half an ans');

    // Still running: nothing yet.
    expect(
      await service.submitExpired(
        student: amina,
        assignments: [a],
        memberKey: 'local/1',
        now: nine.add(const Duration(minutes: 29)),
      ),
      0,
    );
    expect(
      await service.submitExpired(
        student: amina,
        assignments: [a],
        memberKey: 'local/1',
        now: nine.add(const Duration(hours: 3)),
      ),
      1,
    );
    final s = (await mine()).single;
    expect(s.answer, 'Half an ans');
    expect(
      s.createdAt,
      nine.add(const Duration(minutes: 30)).toIso8601String(),
      reason: 'stamped at the deadline, not when the app reopened',
    );
  });

  test('an empty answer is handed in only when time runs out', () async {
    final a = await make();
    await service.start(amina.id, a, now: nine);
    expect(
      await service.submit(
        student: amina,
        assignment: a,
        answer: '  ',
        memberKey: 'local/1',
      ),
      isFalse,
    );
    expect(
      await service.submitExpired(
        student: amina,
        assignments: [a],
        memberKey: 'local/1',
        now: nine.add(const Duration(hours: 1)),
      ),
      1,
    );
    expect((await mine()).single.answer, '');
  });

  test('the start time rides the report to the teacher', () {
    final back = SubmissionPayload.fromJson(
      const SubmissionPayload(
        uuid: 'u',
        assignmentId: 'a',
        subjectId: 's',
        answer: 'x',
        createdAt: '2026-10-12T09:30:00.000Z',
        startedAt: '2026-10-12T09:00:00.000Z',
      ).toJson(),
    )!;
    expect(back.startedAt, '2026-10-12T09:00:00.000Z');
    expect(
      const SubmissionPayload(
        uuid: 'u',
        assignmentId: 'a',
        subjectId: 's',
        answer: 'x',
        createdAt: 'c',
      ).toJson().containsKey('started_at'),
      isFalse,
    );
  });

  test(
    'a learner who never comes back is handed in at the next report',
    () async {
      final groupId = await db
          .into(db.classGroups)
          .insert(
            ClassGroupsCompanion.insert(
              className: 'S2',
              groupUuid: const Value('class-1'),
            ),
          );
      await (db.update(db.students)..where((t) => t.id.equals(amina.id))).write(
        StudentsCompanion(classGroupId: Value(groupId)),
      );
      final a = await make(minutes: 30);
      await service.start(
        amina.id,
        a,
        now: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await service.saveDraft(amina.id, a.id, 'what I had');

      final group = await (db.select(
        db.classGroups,
      )..where((t) => t.id.equals(groupId))).getSingle();
      await buildProgressReports(db, group, deviceKey: 'dev');
      final s = (await mine()).single;
      expect(s.answer, 'what I had');
      expect(s.startedAt, isNotNull);
    },
  );

  test(
    "an assignment's PDF is opened from it, never listed as a note",
    () async {
      final dir = await Directory.systemTemp.createTemp('assessment_pdf');
      addTearDown(() => dir.delete(recursive: true));
      final store = NotePdfStore(db, root: () async => dir);
      await make();
      final title = (await service.own()).single.documentTitle;
      final sha = '0' * 64;
      await store.recordOwn(
        subjectId: 'biology',
        documentTitle: title,
        sha: sha,
        pages: 2,
        bytes: 100,
      );
      await store.recordOwn(
        subjectId: 'biology',
        documentTitle: 'Cells notes',
        sha: '1' * 64,
        pages: 5,
        bytes: 500,
      );
      expect((await store.visibleTo(null)).map((p) => p.documentTitle), [
        'Cells notes',
      ]);
      expect((await store.find(title))?.sha256, sha);
      expect((await db.topicResourceDao.visibleNoteTitles()).map((r) => r.$2), [
        'Cells notes',
      ]);
    },
  );

  group('cloud plug-in', () {
    test('off by default: records are queued, nothing is sent', () async {
      cloud.on = false;
      final a = await make();
      await service.start(amina.id, a);
      await service.submit(
        student: amina,
        assignment: a,
        answer: 'done',
        memberKey: 'local/1',
      );
      expect(await outbox.flush(), 0);
      expect(await outbox.pending(), 2);
      expect(cloud.received, isEmpty);
      expect(
        await CloudOutboxService(db, const DisabledCloudSync()).flush(),
        0,
      );
    });

    test(
      'sends each record once, and keeps them queued while offline',
      () async {
        final a = await make();
        await service.start(amina.id, a);
        await service.submit(
          student: amina,
          assignment: a,
          answer: 'done',
          memberKey: 'local/1',
        );
        cloud.fail = true;
        expect(await outbox.flush(), 0);
        expect(await outbox.pending(), 2);

        cloud.fail = false;
        expect(await outbox.flush(), 2);
        expect(await outbox.flush(), 0, reason: 'nothing doubled');
        final sub = (await mine()).single;
        expect(cloud.received.keys, {
          'assignment:${a.id}',
          'submission:${sub.uuid}',
        });
        expect(
          cloud.received['submission:${sub.uuid}']!.payload['answer'],
          'done',
        );
        expect(
          cloud.received['assignment:${a.id}']!.payload['kind'],
          'holiday',
        );
      },
    );

    test('a grade is one record per version', () async {
      final a = await make();
      await service.start(amina.id, a);
      await service.submit(
        student: amina,
        assignment: a,
        answer: 'done',
        memberKey: 'local/1',
      );
      final uuid = (await mine()).single.uuid;
      await service.grade(uuid, 7, null);
      await service.grade(uuid, 8, 'Good');
      await outbox.flush();
      expect(cloud.received.keys.where((k) => k.startsWith('grade:')), {
        'grade:$uuid:1',
        'grade:$uuid:2',
      });
    });

    test('a record deleted before it was sent is dropped, not sent', () async {
      cloud.on = false;
      final a = await make();
      await service.start(amina.id, a);
      await service.submit(
        student: amina,
        assignment: a,
        answer: 'done',
        memberKey: 'local/1',
      );
      await db.delete(db.assignmentSubmissions).go();
      cloud.on = true;
      await outbox.flush();
      expect(cloud.received.keys, {'assignment:${a.id}'});
      expect(await outbox.pending(), 0);
    });
  });

  test('a v31 database upgrades to v32 and keeps its answers', () async {
    final dir = await Directory.systemTemp.createTemp('otic_migration_test');
    final file = File(p.join(dir.path, 'test.sqlite'));
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final seed = OticDatabase.forTesting(NativeDatabase(file));
    await seed.customStatement(
      "INSERT INTO assignment_submissions (uuid, assignment_id, subject_id, "
      "member_key, learner_name, answer, created_at) VALUES "
      "('u1', 'a1', 'biology', 'm', 'Amina', 'x', '2026-10-01')",
    );
    await seed.customStatement('DROP TABLE assignment_attempts');
    await seed.customStatement('DROP TABLE cloud_outbox');
    await seed.customStatement(
      'ALTER TABLE assignment_submissions DROP COLUMN started_at',
    );
    await seed.customStatement('PRAGMA user_version = 31');
    await seed.close();

    for (var run = 0; run < 2; run++) {
      final upgraded = OticDatabase.forTesting(NativeDatabase(file));
      final rows = await upgraded.select(upgraded.assignmentSubmissions).get();
      expect(rows.single.answer, 'x');
      expect(rows.single.startedAt, isNull);
      expect(await upgraded.select(upgraded.cloudOutbox).get(), isEmpty);
      await upgraded.customStatement('PRAGMA user_version = 31');
      await upgraded.close();
    }
  });
}
