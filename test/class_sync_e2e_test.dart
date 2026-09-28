import 'dart:convert';
import 'dart:io';

import 'package:ai_connect_africa/collaboration/sync/class_crypto.dart';
import 'package:ai_connect_africa/collaboration/sync/selective_sync_manager.dart';
import 'package:ai_connect_africa/collaboration/sync/class_share_server.dart';
import 'package:ai_connect_africa/collaboration/sync/routing_envelope.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
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

    server = ClassShareServer(teacher, joinRounds: _rounds);
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
}
