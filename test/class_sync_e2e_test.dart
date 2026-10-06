import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ai_connect_africa/collaboration/sync/class_crypto.dart';
import 'package:ai_connect_africa/collaboration/sync/selective_sync_manager.dart';
import 'package:ai_connect_africa/collaboration/sync/class_share_server.dart';
import 'package:ai_connect_africa/collaboration/sync/routing_envelope.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/notes/note_pdf_store.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/resource_import_service.dart';
import 'dart:typed_data';
import 'package:drift/drift.dart'
    show Value, DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

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

/// The sharer taps Accept on every join (or Decline, with [accept] false).
/// Returns the names that asked, in order.
List<String> _autoDecide(ClassShareServer server, {bool accept = true}) {
  final asked = <String>[];
  server.pendingJoinsStream.listen((pending) {
    for (final p in pending) {
      asked.add(p.name);
      server.decide(p.id, accept: accept);
    }
  });
  return asked;
}

void main() {
  // Each simulated device is its own database — deliberate, not a leak.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late OticDatabase teacher;
  late ClassShareServer server;
  late ClassGroup east, west;
  late TeacherEndpoint endpoint;
  late Directory teacherPdfDir;
  late NotePdfStore teacherPdfs;
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

    teacherPdfDir = await Directory.systemTemp.createTemp('otic_pdf_t');
    teacherPdfs = NotePdfStore(teacher, root: () async => teacherPdfDir);
    server = ClassShareServer(
      teacher,
      joinRounds: _rounds,
      pdfStore: teacherPdfs,
    );
    _autoDecide(server);
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
    await teacherPdfDir.delete(recursive: true);
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

  test('another sharer’s joins never lock this sharer’s class out', () async {
    // Each device gets its own loopback address, like devices on a Wi-Fi.
    SelectiveSyncManager deviceAt(OticDatabase db, String source) =>
        SelectiveSyncManager(
          db,
          joinRounds: _rounds,
          client: IOClient(
            HttpClient()
              ..connectionFactory = (uri, _, _) => Socket.startConnect(
                uri.host,
                uri.port,
                sourceAddress: source,
              ),
          ),
        );

    final code = await server.openJoinCode(east);

    // Devices joining a different sharer try their proof here first; to
    // this server each is a wrong code. 25 of them, from one busy device…
    final (busyDb, _) = await student();
    final busy = deviceAt(busyDb, '127.0.0.2');
    cleanups.add(() async => busy.dispose());
    for (var i = 0; i < kMaxFailedJoins + 5; i++) {
      await busy.joinClass(teachers: [endpoint], typedCode: 'AAAA-AAAA');
    }
    // …shut out only that device.
    expect(server.joinLocked, isTrue);

    final (db, _) = await student();
    final mine = deviceAt(db, '127.0.0.3');
    cleanups.add(() async => mine.dispose());
    final joined = await mine.joinClass(teachers: [endpoint], typedCode: code!);
    expect(joined.ok, isTrue, reason: joined.error);
    final blocked = await busy.joinClass(teachers: [endpoint], typedCode: code);
    expect(blocked.ok, isFalse, reason: 'the guessing device stays shut out');
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
    final fakeServer = ClassShareServer(fake, joinRounds: _rounds);
    _autoDecide(fakeServer);
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

  test('an address that never answers is skipped quickly', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    // Not routable: a connection attempt hangs rather than being refused,
    // like a remembered address of a device that left the hotspot.
    const dead = (address: '10.255.255.1', port: kDefaultSyncPort);
    final clock = Stopwatch()..start();
    final result = await m.syncClassEverywhere(
      candidates: [dead, endpoint],
      group: group,
    );
    clock.stop();
    expect(result.ok, isTrue, reason: result.error);
    expect(
      {for (final r in await _received(db)) r.resourceTitle},
      {'Acids notes', 'Forces'},
    );
    expect(
      clock.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: 'it used to wait out the 20 s request timeout, twice',
    );
  });

  test('a sync with only dead addresses fails with the usual wording', () async {
    final (_, m) = await student();
    final group = await join(m, east);
    final result = await m.syncClassEverywhere(
      candidates: [(address: '10.255.255.1', port: kDefaultSyncPort)],
      group: group,
    );
    expect(result.ok, isFalse);
    expect(result.error, startsWith('Could not sync with 10.255.255.1.'));
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

  test('received notes are never served as this device’s own', () async {
    final (db, m) = await student();
    final group = await join(m, east);
    await m.syncClass(teacher: endpoint, group: group);

    // The joined class isn't this device's to serve as a teacher…
    expect(await db.classSyncDao.ownedByUuid(group.groupUuid!), isNull);
    expect(
      await ClassShareServer(db, joinRounds: _rounds).openJoinCode(group),
      isNull,
    );
    // …and received notes are never served as if written here, even if
    // shared with a class this device created itself. (Passing them on to
    // classmates, verbatim and teacher-signed, is the classmate role —
    // tested below.)
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

  test('reopening sharing from an old class copy never changes the key',
      () async {
    // `east` was read before the class had a key.
    final first = await teacher.classSyncDao.ensureClassKey(east);
    final again = await teacher.classSyncDao.ensureClassKey(east);
    expect(again.classKey, first.classKey);
  });

  // ── One teacher device; students enroll ─────────────────────────────────

  group('every device can teach; subjects follow their teacher', () {
    test('a device that joined a class can still teach its own, but never '
        'share the joined one as a teacher', () async {
      final (db, m) = await student();
      final g = await join(m, east);
      expect(g.joined, isTrue);
      final own = await _class(db, 'Club', '');
      final host = ClassShareServer(db, joinRounds: _rounds);
      expect(await host.openJoinCode(own), isNotNull);
      expect(await host.openJoinCode(g), isNull);
    });

    test('a device that teaches can join another teacher’s class', () async {
      final (db, m) = await student();
      expect(await db.classSyncDao.claimTeacherRole(), isTrue);
      await _class(db, 'Club', '');
      final g = await join(m, east);
      expect(g.joined, isTrue);
    });

    test('a device can’t join a class it created', () async {
      final m = SelectiveSyncManager(teacher, joinRounds: _rounds);
      cleanups.add(() async => m.dispose());
      final code = await server.openJoinCode(east);
      final r = await m.joinClass(teachers: [endpoint], typedCode: code!);
      expect(r.ok, isFalse);
      expect(r.error, contains('created on this device'));
    });

    test('notes received for a subject this device also teaches are never '
        'listed or deleted as its own', () async {
      final (db, m) = await student();
      await _note(db, 'carpentry', 'Joints', 'A mortise joint holds a tenon.');
      await _note(teacher, 'carpentry', 'Joints', 'A dovetail resists pulling.');
      await teacher.classSyncDao.setShares(
        subjectId: 'carpentry',
        documentTitle: 'Joints',
        classUuids: {east.groupUuid!},
      );
      final g = await join(m, east);
      await m.syncClass(teacher: endpoint, group: g);
      expect(await _received(db), isNotEmpty);

      final storage = OfflineStorageService(db);
      final mine = await storage.listResources(
        subjectId: 'carpentry',
        ownOnly: true,
      );
      expect(mine.single.chunkCount, 1, reason: 'only the own note');

      await storage.deleteTopicResourceByTitle(
        'Joints',
        subjectId: 'carpentry',
      );
      expect(await _received(db), isNotEmpty, reason: 'received note stays');
      await db.topicResourceDao.deleteBySubject('carpentry');
      expect(await _received(db), isNotEmpty, reason: 'received note stays');
    });

    test('a class’s students are offered only the subjects taught to it',
        () async {
      final subjects = CustomSubjectService(
        teacher,
        OfflineStorageService(teacher),
      );
      await subjects.create(name: 'Carpentry');
      await subjects.create(name: 'Fine Art');
      // The Admin assigned a teacher to teach Carpentry to S2 East only.
      await teacher
          .into(teacher.teachingAssignments)
          .insert(
            TeachingAssignmentsCompanion.insert(
              uuid: 'a1',
              teacherId: 1,
              classGroupUuid: east.groupUuid!,
              subjectId: 'carpentry',
              academicYear: 2026,
              createdAt: '2026-10-06T00:00:00Z',
            ),
          );

      final (db, m) = await student();
      final g = await join(m, east);
      await m.syncClass(teacher: endpoint, group: g);
      expect({for (final s in await db.customSubjectDao.all()) s.name}, {
        'Carpentry',
      });
    });

    test('the teacher’s subjects reach students, and follow the teacher’s '
        'edits and removals', () async {
      final subjects = CustomSubjectService(
        teacher,
        OfflineStorageService(teacher),
      );
      await subjects.create(name: 'Carpentry');
      await subjects.create(name: 'Fine Art');

      final (db, m) = await student();
      final g = await join(m, east);
      await m.syncClass(teacher: endpoint, group: g);
      Future<Set<String>> offered() async => {
        for (final s in await db.customSubjectDao.all()) s.name,
      };
      expect(await offered(), {'Carpentry', 'Fine Art'});

      await subjects.rename('fine_art', 'Art and Design');
      await subjects.delete('carpentry');
      await m.syncClass(teacher: endpoint, group: g);
      expect(await offered(), {'Art and Design'});
    });

    test('a bad subject list keeps only well-formed, non-built-in subjects',
        () {
      final ok = offeredSubjects([
        {'id': 'carpentry', 'name': 'Carpentry', 'color': '#00AA00'},
        {'id': 'agriculture', 'name': 'Fake farming'}, // built-in id
        {'id': 'chemistry', 'name': 'Fake chemistry'}, // built-in id
        {'id': 'Bad Id!', 'name': 'x'},
        {'id': 'long', 'name': 'x' * 61},
        'not a map',
      ]);
      expect(ok.map((s) => s.id), ['carpentry']);
      expect(ok.single.color, '#00AA00');
    });

    test('a classmate can’t offer subjects', () async {
      await CustomSubjectService(
        teacher,
        OfflineStorageService(teacher),
      ).create(name: 'Carpentry');
      final (a, ma) = await student();
      final ga = await join(ma, east);
      await ma.syncClass(teacher: endpoint, group: ga);
      // A invents a subject of its own.
      await a.customSubjectDao.insertSubject(
        subjectId: 'fake',
        name: 'Fake',
        icon: 'menu_book',
        color: '#000000',
      );
      final s = ClassShareServer(a, role: ShareRole.classmate, joinRounds: _rounds);
      _autoDecide(s);
      final port = await s.start(classUuids: {ga.groupUuid!}, port: 0);
      cleanups.add(s.stop);

      final (b, mb) = await student();
      await join(mb, east);
      final j = await mb.joinClassmate(
        classmates: [(address: '127.0.0.1', port: port)],
        typedCode: (await s.openJoinCode(ga))!,
      );
      await mb.syncFromClassmate(j.session!);
      expect(await b.customSubjectDao.all(), isEmpty);
    });

    test('the subjects a learner takes reach the teacher', () async {
      final (db, m) = await student();
      final g = await join(m, east);
      final id = await db
          .into(db.students)
          .insert(StudentsCompanion.insert(name: 'Amina'));
      await db.classGroupDao.assignLearner(id, g.id);
      await db.classSyncDao.setEnrolled(id, 'chemistry', true);
      await db.classSyncDao.setEnrolled(id, 'physics', true);
      await db.classSyncDao.setEnrolled(id, 'physics', false);
      await db.classSyncDao.setEnrolled(id, 'biology', true);
      await m.syncClass(teacher: endpoint, group: g);
      final seen = await teacher.classSyncDao
          .watchMemberReports(east.groupUuid!)
          .first;
      expect(seen.single.report.enrolled, ['chemistry', 'biology']);
    });
  });

  // ── Progress back to the teacher ────────────────────────────────────────

  group('students’ progress reaches the teacher', () {
    Future<int> learner(OticDatabase db, String name, int? classId) async {
      final id = await db
          .into(db.students)
          .insert(StudentsCompanion.insert(name: name));
      await db.classGroupDao.assignLearner(id, classId);
      return id;
    }

    Future<List<String>> teacherSees() async => [
      for (final r
          in await teacher.classSyncDao.watchMemberReports(east.groupUuid!).first)
        '${r.report.name}:${r.report.topics.map((t) => '${t.topic}=${t.level}').join(',')}',
    ];

    test('each learner in the class is reported, and only them', () async {
      final (db, m) = await student();
      final g = await join(m, east);
      final amina = await learner(db, 'Amina', g.id);
      await learner(db, 'Brian', g.id);
      await learner(db, 'Visitor', null); // Not in the class.
      await db
          .into(db.topicProgress)
          .insert(
            TopicProgressCompanion.insert(
              studentId: amina,
              topic: 'Acids',
              level: const Value(70),
            ),
          );

      final r = await m.syncClass(teacher: endpoint, group: g);
      expect(r.learnersReported, 2);
      expect(await teacherSees(), ['Amina:Acids=70', 'Brian:']);
    });

    test('a later sync updates the same row, never duplicates', () async {
      final (db, m) = await student();
      final g = await join(m, east);
      final amina = await learner(db, 'Amina', g.id);
      await m.syncClass(teacher: endpoint, group: g);
      await db
          .into(db.topicProgress)
          .insert(
            TopicProgressCompanion.insert(
              studentId: amina,
              topic: 'Bases',
              level: const Value(40),
            ),
          );
      await m.syncClass(teacher: endpoint, group: g);
      expect(await teacherSees(), ['Amina:Bases=40']);
    });

    test('two devices, same learner names, stay separate', () async {
      for (var i = 0; i < 2; i++) {
        final (db, m) = await student();
        final g = await join(m, east);
        await learner(db, 'Amina', g.id);
        await m.syncClass(teacher: endpoint, group: g);
      }
      expect(await teacherSees(), ['Amina:', 'Amina:']);
    });
  });

  // ── Sharer approval ─────────────────────────────────────────────────────

  group('the sharer approves every join', () {
    Future<TeacherEndpoint> teacherServer(ClassShareServer s) async {
      final port = await s.start(classUuids: {east.groupUuid!}, port: 0);
      cleanups.add(s.stop);
      return (address: '127.0.0.1', port: port);
    }

    test('a declined join gets nothing, and the sharer saw the name', () async {
      final strict = ClassShareServer(teacher, joinRounds: _rounds);
      final asked = _autoDecide(strict, accept: false);
      final at = await teacherServer(strict);
      final (db, m) = await student();
      final result = await m.joinClass(
        teachers: [at],
        typedCode: (await strict.openJoinCode(east))!,
        name: 'Amina',
      );
      expect(result.ok, isFalse);
      expect(asked, ['Amina']);
      expect(await db.select(db.classGroups).get(), isEmpty);
    });

    test('nobody answering is a no', () async {
      final slow = ClassShareServer(
        teacher,
        joinRounds: _rounds,
        approvalTimeout: const Duration(milliseconds: 200),
      );
      final at = await teacherServer(slow);
      final (db, m) = await student();
      final result = await m.joinClass(
        teachers: [at],
        typedCode: (await slow.openJoinCode(east))!,
      );
      expect(result.ok, isFalse);
      expect(slow.pendingJoins, isEmpty);
      expect(await db.select(db.classGroups).get(), isEmpty);
    });
  });

  // ── Classmates passing the teacher's notes on ───────────────────────────

  group('a classmate passing notes on', () {
    /// A student device that joined [east] through the teacher and synced.
    Future<(OticDatabase, ClassGroup)> synced() async {
      final (db, m) = await student();
      final g = await join(m, east);
      final r = await m.syncClass(teacher: endpoint, group: g);
      expect(r.ok, isTrue, reason: r.error);
      return (db, g);
    }

    /// Starts [db] sharing [g] with classmates; every join is accepted.
    Future<(ClassShareServer, TeacherEndpoint)> sharing(
      OticDatabase db,
      ClassGroup g,
    ) async {
      final s = ClassShareServer(
        db,
        role: ShareRole.classmate,
        joinRounds: _rounds,
      );
      _autoDecide(s);
      final port = await s.start(classUuids: {g.groupUuid!}, port: 0);
      cleanups.add(s.stop);
      return (s, (address: '127.0.0.1', port: port));
    }

    Future<SyncResult> pull(
      SelectiveSyncManager m,
      ClassShareServer s,
      TeacherEndpoint at,
      ClassGroup g,
    ) async {
      final joined = await m.joinClassmate(
        classmates: [at],
        typedCode: (await s.openJoinCode(g))!,
      );
      expect(joined.ok, isTrue, reason: joined.error);
      return m.syncFromClassmate(joined.session!);
    }

    Future<Map<String, String>> notesOf(OticDatabase db) async => {
      for (final r in await _received(db)) r.resourceTitle: r.contentChunk,
    };

    test('a classmate who missed the teacher gets exactly the teacher’s notes',
        () async {
      final (a, ga) = await synced();
      final (s, at) = await sharing(a, ga);

      // B joined through the teacher, but never synced.
      final (b, mb) = await student();
      await join(mb, east);
      final result = await pull(mb, s, at, ga);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.subjectsUpdated, 2);
      expect(await notesOf(b), await notesOf(a));

      // …and B can then pass it on again: the teacher's signature travels.
      final (s2, at2) = await sharing(b, ga);
      final (c, mc) = await student();
      await join(mc, east);
      await pull(mc, s2, at2, ga);
      expect(await notesOf(c), await notesOf(a));
    });

    test('a device that never joined through the teacher is refused',
        () async {
      final (a, ga) = await synced();
      final (s, at) = await sharing(a, ga);
      final (b, mb) = await student();
      final joined = await mb.joinClassmate(
        classmates: [at],
        typedCode: (await s.openJoinCode(ga))!,
      );
      expect(joined.ok, isFalse);
      expect(joined.error, contains('teacher’s code first'));
      expect(await _received(b), isEmpty);
    });

    test('the class key alone does not get notes from a classmate', () async {
      final (a, ga) = await synced();
      final (_, at) = await sharing(a, ga);
      final body = jsonEncode({'school_id': ga.schoolId});
      final nonce = newNonce();
      final r = await http.post(
        Uri.parse('http://127.0.0.1:${at.port}/$kHandshakePath'),
        headers: {
          kClassHeader: ga.groupUuid!,
          kNonceHeader: nonce,
          kMacHeader: await requestMac(
            classKey: ga.classKey!,
            path: kHandshakePath,
            nonce: nonce,
            body: body,
          ),
        },
        body: body,
      );
      expect(r.statusCode, 404);
      expect(r.body, isEmpty);
    });

    test('an edited note is rejected and the old copy kept', () async {
      final (a, ga) = await synced();
      final (b, mb) = await student();
      final gb = await join(mb, east);
      // B has an older copy from the teacher; then the teacher edits.
      await mb.syncClass(teacher: endpoint, group: gb);
      final before = await notesOf(b);

      await (a.update(a.topicResources)
            ..where((t) => t.resourceTitle.equals('Forces')))
          .write(
            const TopicResourcesCompanion(
              contentChunk: Value('A force is imaginary.'),
            ),
          );
      // Pretend it's newer so B would take it if it trusted A.
      await (a.update(a.syncState)..where((t) => t.subjectId.equals('physics')))
          .write(const SyncStateCompanion(channelVersion: Value(99)));

      final (s, at) = await sharing(a, ga);
      final result = await pull(mb, s, at, ga);
      expect(result.subjectsUpdated, 0);
      expect(result.rejected, isNotEmpty);
      expect(await notesOf(b), before);
    });

    test('notes re-signed by a classmate’s own key are rejected', () async {
      final (a, ga) = await synced();
      const forged = 'A force is imaginary.';
      await (a.update(a.topicResources)
            ..where((t) => t.resourceTitle.equals('Forces')))
          .write(const TopicResourcesCompanion(contentChunk: Value(forged)));
      // Recompute the digest over the edited chunk and sign it — with a key
      // that isn't the teacher's.
      final rows = await a.classSyncDao.receivedChunks(ga.groupUuid!, 'physics');
      final ids = [
        for (final r in rows)
          ResourceChunkEnvelope.forChannel(
            classGroupUuid: ga.groupUuid!,
            subjectId: r.subjectId,
            topicKey: r.topicKey,
            termMarker: r.termMarker,
            resourceTitle: r.resourceTitle,
            contentChunk: r.contentChunk,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            documentTitle: r.documentTitle,
          ).chunkId,
      ];
      final digest = await channelDigest(ids);
      await (a.update(a.syncState)..where((t) => t.subjectId.equals('physics')))
          .write(
            SyncStateCompanion(
              channelDigest: Value(digest),
              channelVersion: const Value(99),
              manifestSig: Value(
                await signManifest(
                  signingSeed: newSigningSeed(),
                  schoolId: ga.schoolId!,
                  classUuid: ga.groupUuid!,
                  subjectId: 'physics',
                  digest: digest,
                  version: 99,
                ),
              ),
            ),
          );

      final (s, at) = await sharing(a, ga);
      final (b, mb) = await student();
      await join(mb, east);
      final result = await pull(mb, s, at, ga);
      expect(result.rejected.map((r) => r.reason), contains(contains('teacher')));
      expect((await notesOf(b)).values.join(), isNot(contains(forged)));
    });

    test('an older copy never rolls a classmate back', () async {
      final (a, ga) = await synced(); // A holds the first version.
      await OfflineStorageService(
        teacher,
      ).deleteTopicResourceByTitle('Acids notes', subjectId: 'chemistry');
      await _note(teacher, 'chemistry', 'Acids notes', 'Acids have pH < 7.');
      await teacher.classSyncDao.setShares(
        subjectId: 'chemistry',
        documentTitle: 'Acids notes',
        classUuids: {east.groupUuid!},
      );
      final (b, mb) = await student();
      final gb = await join(mb, east);
      await mb.syncClass(teacher: endpoint, group: gb); // B: newer version.

      final (s, at) = await sharing(a, ga);
      final result = await pull(mb, s, at, ga);
      expect(result.subjectsUpdated, 0);
      expect((await notesOf(b))['Acids notes'], contains('pH < 7'));
    });

    test('a subject the teacher removed doesn’t come back via a classmate',
        () async {
      final (a, ga) = await synced(); // A has physics.
      final (c, mc) = await student();
      final gc = await join(mc, east);
      await mc.syncClass(teacher: endpoint, group: gc); // So has C…

      await teacher.classSyncDao.setShares(
        subjectId: 'physics',
        documentTitle: 'Forces',
        classUuids: {},
      );
      final removed = await mc.syncClass(teacher: endpoint, group: gc);
      expect(removed.subjectsRemoved, 1); // …until the teacher unshares it.

      final (s, at) = await sharing(a, ga);
      await pull(mc, s, at, ga);
      expect((await notesOf(c)).keys, isNot(contains('Forces')));
    });

    test('a classmate never deletes anything', () async {
      final (a, ga) = await synced();
      // A no longer has physics at all.
      await (a.delete(a.topicResources)
            ..where((t) => t.subjectId.equals('physics')))
          .go();
      await (a.delete(a.syncState)..where((t) => t.subjectId.equals('physics')))
          .go();
      final (b, mb) = await student();
      final gb = await join(mb, east);
      await mb.syncClass(teacher: endpoint, group: gb);

      final (s, at) = await sharing(a, ga);
      await pull(mb, s, at, ga);
      expect((await notesOf(b)).keys, contains('Forces'));
    });
  });

  group('a note’s original PDF', () {
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 acids and bases'));

    Future<(OticDatabase, SelectiveSyncManager, NotePdfStore)> pdfStudent() async {
      final db = _db();
      final dir = await Directory.systemTemp.createTemp('otic_pdf_s');
      final store = NotePdfStore(
        db,
        root: () async => dir,
        gcGrace: Duration.zero,
      );
      final manager = SelectiveSyncManager(
        db,
        joinRounds: _rounds,
        pdfStore: store,
      );
      cleanups.add(() async {
        manager.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
      return (db, manager, store);
    }

    Future<String> keepOnTeacher() async {
      final sha = (await teacherPdfs.put(pdf))!;
      await teacherPdfs.recordOwn(
        subjectId: 'chemistry',
        documentTitle: 'Acids notes',
        sha: sha,
        pages: 3,
        bytes: pdf.length,
      );
      return sha;
    }

    test('reaches the class with the note, once', () async {
      final sha = await keepOnTeacher();
      final (_, m, store) = await pdfStudent();
      final group = await join(m, east);
      final first = await m.syncClass(teacher: endpoint, group: group);
      expect(first.ok, isTrue, reason: first.error);
      expect(first.pdfsFetched, 1);
      expect(await (await store.fileFor(sha))!.readAsBytes(), pdf);
      final found = await store.find('Acids notes', classUuid: group.groupUuid);
      expect(found?.pages, 3);

      final again = await m.syncClass(teacher: endpoint, group: group);
      expect(again.pdfsFetched, 0, reason: 'already on the device');
    });

    test('never goes to a class the note isn’t shared with', () async {
      await keepOnTeacher();
      final (_, m, store) = await pdfStudent();
      final group = await join(m, west);
      final r = await m.syncClass(teacher: endpoint, group: group);
      expect(r.pdfsFetched, 0);
      expect(await store.recorded(classUuid: group.groupUuid), isEmpty);
    });

    test('a file that doesn’t match the signed hash is refused', () async {
      final sha = await keepOnTeacher();
      // Swapped on disk after the note was recorded.
      await File('${teacherPdfDir.path}${Platform.pathSeparator}$sha.pdf')
          .writeAsBytes(utf8.encode('%PDF-1.4 something else'));
      final (_, m, store) = await pdfStudent();
      final group = await join(m, east);
      final r = await m.syncClass(teacher: endpoint, group: group);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.pdfsFetched, 0);
      expect(await store.has(sha), isFalse);
    });

    test('unsharing the note removes the PDF too', () async {
      final sha = await keepOnTeacher();
      final (_, m, store) = await pdfStudent();
      final group = await join(m, east);
      await m.syncClass(teacher: endpoint, group: group);
      expect(await store.has(sha), isTrue);

      await teacher.classSyncDao.setShares(
        subjectId: 'chemistry',
        documentTitle: 'Acids notes',
        classUuids: {},
      );
      await m.syncClass(teacher: endpoint, group: group);
      expect(await store.has(sha), isFalse);
    });

    test('a 15 MB PDF arrives via the student screen’s sync, and another '
        'student isn’t held up meanwhile', () async {
      final rnd = Random(7);
      final big = Uint8List.fromList(
        List<int>.generate(15 * 1024 * 1024, (_) => rnd.nextInt(256)),
      );
      final sha = (await teacherPdfs.put(big))!;
      await teacherPdfs.recordOwn(
        subjectId: 'chemistry',
        documentTitle: 'Acids notes',
        sha: sha,
        pages: 120,
        bytes: big.length,
      );
      final (_, m, store) = await pdfStudent();
      final group = await join(m, east);
      final (_, other) = await student();
      final otherGroup = await join(other, west);

      final clock = Stopwatch()..start();
      final download = m.syncClassEverywhere(
        candidates: [endpoint],
        group: group,
      );
      // Started while the PDF is in flight.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final quick = Stopwatch()..start();
      final small = await other.syncClass(
        teacher: endpoint,
        group: otherGroup,
      );
      quick.stop();
      final r = await download;
      clock.stop();
      // ignore: avoid_print
      print('15 MB PDF sync: ${clock.elapsedMilliseconds} ms; other '
          'student’s sync meanwhile: ${quick.elapsedMilliseconds} ms');

      expect(r.ok, isTrue, reason: r.error);
      expect(r.pdfsFetched, 1, reason: 'counted through syncClassEverywhere');
      expect(await (await store.fileFor(sha))!.length(), big.length);
      expect(small.ok, isTrue, reason: small.error);
      expect(quick.elapsed, lessThan(const Duration(seconds: 5)));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('the tutor never retrieves the PDF record as notes', () async {
      await keepOnTeacher();
      final hits = await teacher.topicResourceDao.searchAllChunks(
        needle: 'PDF sha256 pages bytes',
      );
      expect(hits.where((h) => h.topicKey == kPdfMarkerTopic), isEmpty);
    });
  });
}
