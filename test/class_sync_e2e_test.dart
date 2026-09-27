import 'dart:convert';

import 'package:ai_connect_africa/collaboration/sync/class_crypto.dart';
import 'package:ai_connect_africa/collaboration/sync/selective_sync_manager.dart';
import 'package:ai_connect_africa/collaboration/sync/teacher_sync_server.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/resource_import_service.dart';
import 'dart:typed_data';
import 'package:drift/drift.dart'
    show Value, DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Class sync end to end: a teacher device's server, student devices'
/// clients, in-memory databases, real HTTP on localhost.
const _rounds = 1000; // PBKDF2 rounds — the real value is deliberately slow.

OticDatabase _db() =>
    OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));

Future<ClassGroup> _class(OticDatabase db, String name, String stream) async {
  final id = await db.classGroupDao.createClass(
    className: name,
    streamName: stream,
  );
  return (db.select(db.classGroups)..where((t) => t.id.equals(id))).getSingle();
}

Future<void> _note(
  OticDatabase db,
  String subject,
  String title,
  String body,
) => OfflineStorageService(db).insertTopicResource(
  subjectId: subject,
  topicKey: 'topic',
  resourceTitle: title,
  content: body,
);

Future<List<TopicResource>> _received(OticDatabase db) => (db.select(
  db.topicResources,
)..where((t) => t.classGroupUuid.isNotNull())).get();

void main() {
  // Each simulated device is its own database — deliberate, not a leak.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late OticDatabase teacher;
  late TeacherSyncServer server;
  late ClassGroup east, west;
  late TeacherEndpoint endpoint;
  final cleanups = <Future<void> Function()>[];

  setUp(() async {
    teacher = _db();
    await teacher.classSyncDao.setSchoolName('Bright Future Academy');
    east = await _class(teacher, 'S2', 'East');
    west = await _class(teacher, 'S2', 'West');
    await _note(
      teacher,
      'chemistry',
      'Acids notes',
      'Acids turn blue litmus red.',
    );
    await _note(
      teacher,
      'chemistry',
      'Bases notes',
      'Bases turn red litmus blue.',
    );
    await _note(teacher, 'biology', 'Cells', 'Cells are the unit of life.');
    await _note(teacher, 'physics', 'Forces', 'A force is a push or a pull.');
    final share = teacher.classSyncDao.setShares;
    await share(
      subjectId: 'chemistry',
      documentTitle: 'Acids notes',
      classUuids: {east.groupUuid!},
    );
    await share(
      subjectId: 'physics',
      documentTitle: 'Forces',
      classUuids: {east.groupUuid!},
    );
    await share(
      subjectId: 'biology',
      documentTitle: 'Cells',
      classUuids: {west.groupUuid!},
    );
    // "Bases notes" is shared with nobody.

    server = TeacherSyncServer(teacher, joinRounds: _rounds);
    final port = await server.start(
      classUuids: {east.groupUuid!, west.groupUuid!},
      port: 0,
    );
    endpoint = (address: '127.0.0.1', port: port);
  });

  tearDown(() async {
    for (final c in cleanups.reversed) {
      await c();
    }
    cleanups.clear();
    await server.stop();
    await teacher.close();
  });

  Future<(OticDatabase, SelectiveSyncManager)> student({String? school}) async {
    final db = _db();
    if (school != null) await db.classSyncDao.setSchoolName(school);
    final manager = SelectiveSyncManager(db, joinRounds: _rounds);
    cleanups.add(() async {
      manager.dispose();
      await db.close();
    });
    return (db, manager);
  }

  Future<ClassGroup> join(SelectiveSyncManager m, ClassGroup group) async {
    final code = await server.openJoinCode(group);
    final result = await m.joinClass(teachers: [endpoint], typedCode: code!);
    expect(result.error, isNull);
    return result.group!;
  }

  test(
    'a joined student gets only the notes shared with their class',
    () async {
      final (db, m) = await student();
      final code = await server.openJoinCode(east);
      // Typed loosely: lower case, a space instead of the hyphen.
      final joined = await m.joinClass(
        teachers: [endpoint],
        typedCode: code!.toLowerCase().replaceAll('-', ' '),
      );
      expect(joined.ok, isTrue, reason: joined.error);
      expect(joined.schoolName, 'Bright Future Academy');
      expect(
        joined.group!.groupUuid,
        east.groupUuid,
        reason: 'the teacher’s class id, not a new one',
      );
      expect(
        (await db.classSyncDao.identity()).schoolName,
        'Bright Future Academy',
      );

      final result = await m.syncClass(teacher: endpoint, group: joined.group!);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.subjectsChecked, 2);

      final titles = {for (final r in await _received(db)) r.resourceTitle};
      expect(titles, {'Acids notes', 'Forces'});
      expect(titles, isNot(contains('Bases notes')), reason: 'never shared');
      expect(
        titles,
        isNot(contains('Cells')),
        reason: 'shared with S2 West, not East',
      );
    },
  );

  test('a device from another school cannot join', () async {
    final (db, m) = await student(school: 'Hilltop College');
    final code = await server.openJoinCode(east);
    final result = await m.joinClass(teachers: [endpoint], typedCode: code!);
    expect(result.ok, isFalse);
    expect(result.error, contains('Hilltop College'));
    expect(await (db.select(db.classGroups)).get(), isEmpty);
  });

  test('wrong codes fail, and too many lock every code', () async {
    final (_, m) = await student();
    final code = await server.openJoinCode(east);
    final wrong = await m.joinClass(
      teachers: [endpoint],
      typedCode: 'AAAA-AAAA',
    );
    expect(wrong.ok, isFalse);
    for (var i = 1; i < kMaxFailedJoins; i++) {
      await m.joinClass(teachers: [endpoint], typedCode: 'AAAA-AAAA');
    }
    expect(server.joinLocked, isTrue);
    final right = await m.joinClass(teachers: [endpoint], typedCode: code!);
    expect(
      right.ok,
      isFalse,
      reason: 'locked after $kMaxFailedJoins wrong codes',
    );
  });

  test('an expired code fails', () async {
    final (_, m) = await student();
    final code = await server.openJoinCode(
      east,
      ttl: const Duration(milliseconds: -1),
    );
    expect(
      (await m.joinClass(teachers: [endpoint], typedCode: code!)).ok,
      isFalse,
    );
  });

  test('a class the teacher is not sharing right now cannot sync', () async {
    final (_, m) = await student();
    final group = await join(m, west);
    server.serving.remove(west.groupUuid);
    final result = await m.syncClass(teacher: endpoint, group: group);
    expect(result.ok, isFalse);
  });

  test(
    'unknown class, bad MAC and wrong school all get the same bare 404',
    () async {
      final keyed = await teacher.classSyncDao.ensureClassKey(east);
      Future<http.Response> post(
        String classUuid,
        String key,
        String school,
      ) async {
        final body = jsonEncode({'school_id': school});
        final nonce = newNonce();
        return http.post(
          Uri.parse('http://127.0.0.1:${endpoint.port}/$kHandshakePath'),
          headers: {
            kClassHeader: classUuid,
            kNonceHeader: nonce,
            kMacHeader: await requestMac(
              classKey: key,
              path: kHandshakePath,
              nonce: nonce,
              body: body,
            ),
          },
          body: body,
        );
      }

      final good = await post(
        east.groupUuid!,
        keyed.classKey!,
        keyed.schoolId!,
      );
      expect(good.statusCode, 200);
      final responses = [
        await post('no-such-class', keyed.classKey!, keyed.schoolId!),
        await post(east.groupUuid!, newClassKey(), keyed.schoolId!),
        await post(east.groupUuid!, keyed.classKey!, 'another-school'),
      ];
      for (final r in responses) {
        expect(r.statusCode, 404);
        expect(r.body, isEmpty);
      }
    },
  );

  test('a classmate running a fake teacher server is rejected', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    await m.syncClass(teacher: endpoint, group: group);

    // A classmate holds the class id, key and school — but not the teacher's
    // signing key.
    final fake = _db();
    await fake
        .into(fake.classGroups)
        .insert(
          ClassGroupsCompanion.insert(
            className: 'S2',
            streamName: const Value('East'),
            groupUuid: Value(group.groupUuid),
            classKey: Value(group.classKey),
            schoolId: Value(group.schoolId),
          ),
        );
    await _note(
      fake,
      'chemistry',
      'Acids notes',
      'Acids are harmless to drink.',
    );
    await fake.classSyncDao.setShares(
      subjectId: 'chemistry',
      documentTitle: 'Acids notes',
      classUuids: {group.groupUuid!},
    );
    final fakeServer = TeacherSyncServer(fake, joinRounds: _rounds);
    final fakePort = await fakeServer.start(
      classUuids: {group.groupUuid!},
      port: 0,
    );
    cleanups.add(() async {
      await fakeServer.stop();
      await fake.close();
    });

    final result = await m.syncClass(
      teacher: (address: '127.0.0.1', port: fakePort),
      group: group,
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('isn’t your class’s teacher'));
    final bodies = (await _received(db)).map((r) => r.contentChunk).join();
    expect(bodies, contains('blue litmus red'));
    expect(bodies, isNot(contains('harmless')));
  });

  test('an edited note replaces the old copy, with no duplicates', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    await m.syncClass(teacher: endpoint, group: group);

    await OfflineStorageService(
      teacher,
    ).deleteTopicResourceByTitle('Acids notes', subjectId: 'chemistry');
    await _note(
      teacher,
      'chemistry',
      'Acids notes',
      'Acids have a pH below 7.',
    );
    await teacher.classSyncDao.setShares(
      subjectId: 'chemistry',
      documentTitle: 'Acids notes',
      classUuids: {east.groupUuid!},
    );

    final result = await m.syncClass(teacher: endpoint, group: group);
    expect(result.ok, isTrue, reason: result.error);
    final acids = (await _received(
      db,
    )).where((r) => r.resourceTitle == 'Acids notes').toList();
    expect(acids, hasLength(1));
    expect(acids.single.contentChunk, contains('pH below 7'));
  });

  test('unsharing removes the notes from the student device', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    await m.syncClass(teacher: endpoint, group: group);

    await teacher.classSyncDao.setShares(
      subjectId: 'physics',
      documentTitle: 'Forces',
      classUuids: {},
    );
    final result = await m.syncClass(teacher: endpoint, group: group);
    expect(result.subjectsRemoved, 1);
    expect(
      {for (final r in await _received(db)) r.resourceTitle},
      {'Acids notes'},
    );
    expect(
      await db.classSyncDao.channelDigestFor(group.groupUuid!, 'physics'),
      isNull,
    );
  });

  test('a student device never passes received notes on', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    await m.syncClass(teacher: endpoint, group: group);

    // The joined class isn't this device's to serve…
    expect(await db.classSyncDao.ownedByUuid(group.groupUuid!), isNull);
    // …and received notes are never served, even if shared with a class
    // this device created itself.
    final club = await _class(db, 'Science club', '');
    await db.classSyncDao.setShares(
      subjectId: 'chemistry',
      documentTitle: 'Acids notes',
      classUuids: {club.groupUuid!},
    );
    expect(
      await db.classSyncDao.sharedChunks(club.groupUuid!, 'chemistry'),
      isEmpty,
    );
  });

  test(
    'on a shared device each learner is tutored only from their own class',
    () async {
      final (db, m) = await student();
      final eastGroup = await join(m, east);
      final westGroup = await join(m, west);
      await m.syncClass(teacher: endpoint, group: eastGroup);
      await m.syncClass(teacher: endpoint, group: westGroup);

      Future<Set<String>> tutorSees(String? classUuid, String words) async => {
        for (final r in await OfflineStorageService(
          db,
          visibleClassUuid: classUuid,
        ).searchAllChunks(needle: words))
          r.resourceTitle,
      };
      expect(await tutorSees(eastGroup.groupUuid, 'cells life'), isEmpty);
      expect(await tutorSees(westGroup.groupUuid, 'cells life'), {'Cells'});
      expect(await tutorSees(eastGroup.groupUuid, 'acids litmus'), {
        'Acids notes',
      });
      expect(
        await tutorSees(null, 'acids litmus cells'),
        isEmpty,
        reason: 'no class, no received notes',
      );
    },
  );

  test(
    'an uploaded file is one note to people, however it is split inside',
    () async {
      final text = [
        'ACIDS',
        List.filled(
          8,
          'Acids turn blue litmus paper red and taste sour.',
        ).join(' '),
        'BASES',
        List.filled(
          8,
          'Bases turn red litmus paper blue and feel soapy.',
        ).join(' '),
        'INDICATORS',
        List.filled(
          8,
          'Indicators change colour at a particular pH value.',
        ).join(' '),
      ].join('\n');
      final report = await ResourceImportService(OfflineStorageService(teacher))
          .importBytes(
            fileName: 'Chemistry_Term_1.txt',
            bytes: Uint8List.fromList(utf8.encode(text)),
            subjectId: 'chemistry',
          );
      expect(report.ok, isTrue, reason: report.failure);
      expect(
        report.topics.length,
        3,
        reason: 'still split at headings for the tutor',
      );

      // The teacher's list shows the file once, not its three sections.
      final teacherList = await OfflineStorageService(
        teacher,
      ).listResources(subjectId: 'chemistry');
      expect(
        teacherList
            .map((r) => r.resourceTitle)
            .where((t) => t.startsWith('Chemistry Term 1')),
        ['Chemistry Term 1'],
      );

      // Sharing the file shares every section of it.
      await teacher.classSyncDao.setShares(
        subjectId: 'chemistry',
        documentTitle: 'Chemistry Term 1',
        classUuids: {east.groupUuid!},
      );
      final (db, m) = await student();
      final group = await join(m, east);
      await m.syncClass(teacher: endpoint, group: group);
      final studentList = await OfflineStorageService(
        db,
      ).listResources(subjectId: 'chemistry');
      expect(
        studentList.map((r) => r.resourceTitle),
        contains('Chemistry Term 1'),
      );
      expect(
        studentList.where((r) => r.resourceTitle.contains('—')),
        isEmpty,
        reason: 'no section pieces shown on the student device either',
      );
      final received = (await _received(db)).map((r) => r.contentChunk).join();
      expect(
        received,
        allOf(
          contains('taste sour'),
          contains('feel soapy'),
          contains('pH value'),
        ),
      );

      // Deleting the file removes every section and its shares.
      await OfflineStorageService(
        teacher,
      ).deleteTopicResourceByTitle('Chemistry Term 1', subjectId: 'chemistry');
      final left = (await teacher.select(teacher.topicResources).get()).where(
        (r) => r.resourceTitle.startsWith('Chemistry Term 1'),
      );
      expect(left, isEmpty);
      expect(
        await teacher.select(teacher.resourceShares).get(),
        everyElement(
          isA<ResourceShare>().having(
            (s) => s.documentTitle,
            'document',
            isNot('Chemistry Term 1'),
          ),
        ),
      );
    },
  );

  test('deleting a joined class removes what it received', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    await m.syncClass(teacher: endpoint, group: group);
    await db.classGroupDao.deleteClass(group.id);
    expect(await _received(db), isEmpty);
    expect(
      await db.classSyncDao.channelDigestFor(group.groupUuid!, 'chemistry'),
      isNull,
    );
  });
}
