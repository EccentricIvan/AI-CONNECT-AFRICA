import 'package:ai_connect_africa/collaboration/sync/class_crypto.dart';
import 'package:ai_connect_africa/collaboration/sync/class_share_server.dart';
import 'package:ai_connect_africa/collaboration/sync/failover_crypto.dart';
import 'package:ai_connect_africa/collaboration/sync/p2p_failover_service.dart';
import 'package:ai_connect_africa/collaboration/sync/selective_sync_manager.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/tables/sync_identity_table.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host failover end to end: a teacher device, a paired standby, a student
/// device, real HTTP on localhost, in-memory databases.
const _rounds = 1000; // PBKDF2 — the real values are deliberately slow.
const _passphrase = 'mango trees by the river';

OticDatabase _db() =>
    OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));

Future<void> _note(OticDatabase db, String subject, String title, String body) =>
    OfflineStorageService(db).insertTopicResource(
      subjectId: subject,
      topicKey: 'topic',
      resourceTitle: title,
      content: body,
    );

Future<Set<String>> _receivedTitles(OticDatabase db) async => {
  for (final r in await (db.select(
    db.topicResources,
  )..where((t) => t.classGroupUuid.isNotNull())).get())
    r.resourceTitle,
};

void _autoAccept(ClassShareServer server) =>
    server.pendingJoinsStream.listen((pending) {
      for (final p in pending) {
        server.decide(p.id, accept: true);
      }
    });

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late OticDatabase teacher, standby, student;
  late ClassShareServer teacherServer;
  late TeacherEndpoint teacherAt;
  late ClassGroup east;
  late P2PFailoverService teacherFailover, standbyFailover;
  late SelectiveSyncManager studentSync;
  ClassShareServer? standbyServer;

  setUp(() async {
    teacher = _db();
    standby = _db();
    student = _db();
    await teacher.classSyncDao.setSchoolName('Bright Future Academy');
    await teacher.classSyncDao.claimTeacherRole();
    final id = await teacher.classGroupDao.createClass(
      className: 'S2',
      streamName: 'East',
    );
    east = await (teacher.select(
      teacher.classGroups,
    )..where((t) => t.id.equals(id))).getSingle();
    await _note(teacher, 'chemistry', 'Acids', 'Acids turn blue litmus red.');
    await _note(teacher, 'physics', 'Forces', 'A force is a push or a pull.');
    await _note(teacher, 'physics', 'Private', 'Never shared.');
    for (final (subject, doc) in [('chemistry', 'Acids'), ('physics', 'Forces')]) {
      await teacher.classSyncDao.setShares(
        subjectId: subject,
        documentTitle: doc,
        classUuids: {east.groupUuid!},
      );
    }

    teacherServer = ClassShareServer(teacher, joinRounds: _rounds);
    _autoAccept(teacherServer);
    final port = await teacherServer.start(
      classUuids: {east.groupUuid!},
      port: 0,
    );
    teacherAt = (address: '127.0.0.1', port: port);

    teacherFailover = P2PFailoverService(teacher, kdfRounds: _rounds);
    standbyFailover = P2PFailoverService(
      standby,
      kdfRounds: _rounds,
      joinRounds: _rounds,
    );

    // The student joins and syncs with the original teacher device.
    studentSync = SelectiveSyncManager(student, joinRounds: _rounds);
    final code = await teacherServer.openJoinCode(east);
    final joined = await studentSync.joinClass(
      teachers: [teacherAt],
      typedCode: code!,
    );
    expect(joined.ok, isTrue, reason: joined.error);
    final first = await studentSync.syncClass(
      teacher: teacherAt,
      group: joined.group!,
    );
    expect(first.ok, isTrue, reason: first.error);
    expect(await _receivedTitles(student), {'Acids', 'Forces'});
  });

  tearDown(() async {
    teacherFailover.dispose();
    standbyFailover.dispose();
    studentSync.dispose();
    await teacherServer.stop();
    await standbyServer?.stop();
    standbyServer = null;
    await teacher.close();
    await standby.close();
    await student.close();
  });

  Future<ClassGroup> studentGroup() async =>
      (await student.classSyncDao.joinedByUuid(east.groupUuid!))!;

  /// Passphrase on, standby paired and holding a ledger.
  Future<void> pairStandby() async {
    expect((await teacherFailover.enableFailover(_passphrase)).ok, isTrue);
    final code = await teacherServer.openStandbyCode();
    expect(code, isNotNull);
    final paired = await standbyFailover.pairAsStandby(
      hosts: [teacherAt],
      typedCode: code!,
      name: 'Deputy head laptop',
    );
    expect(paired.error, isNull);
  }

  /// The teacher device dies; the standby takes over and starts sharing.
  Future<TeacherEndpoint> promoteAndServe() async {
    await teacherServer.stop();
    final ledger = await standbyFailover.storedLedger();
    final result = await standbyFailover.promoteToHostNode(_passphrase, ledger!);
    expect(result.error, isNull);
    final server = standbyServer = ClassShareServer(standby, joinRounds: _rounds);
    final port = await server.start(classUuids: {east.groupUuid!}, port: 0);
    return (address: '127.0.0.1', port: port);
  }

  test('a short passphrase is refused', () async {
    final r = await teacherFailover.enableFailover('short');
    expect(r.ok, isFalse);
    expect(await teacherServer.openStandbyCode(), isNull);
  });

  test('pairing pins the standby and leaves a sealed ledger on it', () async {
    await pairStandby();
    final row = await standbyFailover.storedLedgerRow();
    expect(row!.sealedJson, isNotNull);
    expect(
      row.rootPublicKey,
      await signingPublicKey((await teacher.classSyncDao.identity()).signingSeed),
    );
    expect(row.sealedJson, isNot(contains('Acids turn blue')));
    expect(await teacher.select(teacher.failoverStandbys).get(), hasLength(1));
  });

  test('an unpaired device cannot pull the ledger', () async {
    expect((await teacherFailover.enableFailover(_passphrase)).ok, isTrue);
    await standby
        .into(standby.hostLedgers)
        .insert(
          HostLedgersCompanion.insert(
            rootPublicKey: 'x',
            schoolId: 'y',
            schoolName: 'z',
          ),
        );
    final r = await standbyFailover.pullLedger([teacherAt]);
    expect(r.ok, isFalse);
  });

  test('a wrong passphrase changes nothing', () async {
    await pairStandby();
    final before = await standby.classSyncDao.identity();
    final r = await standbyFailover.promoteToHostNode(
      'not the right passphrase',
      (await standbyFailover.storedLedger())!,
    );
    expect(r.ok, isFalse);
    final after = await standby.classSyncDao.identity();
    expect(after.signingSeed, before.signingSeed);
    expect(after.deviceRole, isNot(kRoleTeacher));
    expect(await standby.classSyncDao.ownedClasses(), isEmpty);
  });

  test('a student device cannot be promoted', () async {
    await pairStandby();
    final r = await P2PFailoverService(
      student,
      kdfRounds: _rounds,
    ).promoteToHostNode(_passphrase, (await standbyFailover.storedLedger())!);
    expect(r.ok, isFalse);
  });

  test('students reconnect to the promoted host with nothing lost, and '
      'new notes reach them', () async {
    await pairStandby();
    final newHost = await promoteAndServe();

    final me = await standby.classSyncDao.identity();
    expect(me.deviceRole, kRoleTeacher);
    expect(me.hostGeneration, 1);
    expect(
      await signingPublicKey(me.signingSeed),
      (await studentGroup()).teacherPublicKey,
      reason: 'the key students pinned at join',
    );

    final again = await studentSync.syncClass(
      teacher: newHost,
      group: await studentGroup(),
    );
    expect(again.ok, isTrue, reason: again.error);
    expect(again.subjectsRemoved, 0);
    expect(again.subjectsUpdated, 0, reason: 'same notes, same digests');
    expect(await _receivedTitles(student), {'Acids', 'Forces'});
    expect((await studentGroup()).hostEpoch, 1);
    expect(await student.classSyncDao.deviceRole(), kRoleStudent);

    // The new host edits the class's notes; students take the change.
    await _note(standby, 'chemistry', 'Bases', 'Bases turn red litmus blue.');
    await standby.classSyncDao.setShares(
      subjectId: 'chemistry',
      documentTitle: 'Bases',
      classUuids: {east.groupUuid!},
    );
    final third = await studentSync.syncClass(
      teacher: newHost,
      group: await studentGroup(),
    );
    expect(third.ok, isTrue, reason: third.error);
    expect(await _receivedTitles(student), {'Acids', 'Bases', 'Forces'});
  });

  test('the old teacher device is refused once it comes back', () async {
    await pairStandby();
    final newHost = await promoteAndServe();
    expect(
      (await studentSync.syncClass(
        teacher: newHost,
        group: await studentGroup(),
      )).ok,
      isTrue,
    );

    // The old phone is found and switched on, its notes now different.
    await teacher.classSyncDao.setShares(
      subjectId: 'physics',
      documentTitle: 'Forces',
      classUuids: {},
    );
    final port = await teacherServer.start(
      classUuids: {east.groupUuid!},
      port: 0,
    );
    final stale = await studentSync.syncClass(
      teacher: (address: '127.0.0.1', port: port),
      group: await studentGroup(),
    );
    expect(stale.ok, isFalse);
    expect(stale.error, contains('replaced'));
    expect(
      await _receivedTitles(student),
      {'Acids', 'Forces'},
      reason: 'the old device dropped nothing',
    );
  });

  test('versions signed after takeover outrank the old host', () async {
    await pairStandby();
    await promoteAndServe();
    final channels = await standby.select(standby.servedChannels).get();
    expect(channels, isNotEmpty);
    for (final c in channels) {
      expect(c.version, greaterThan(generationFloor(1)));
    }
  });

  test('promotion is offline and idempotent with a USB-carried ledger',
      () async {
    expect((await teacherFailover.enableFailover(_passphrase)).ok, isTrue);
    final usb = (await teacherFailover.exportLedger())!;
    expect(ledgerHeader(usb), isNotNull);
    final fresh = P2PFailoverService(standby, kdfRounds: _rounds);
    final a = await fresh.promoteToHostNode(_passphrase, usb);
    final b = await fresh.promoteToHostNode(_passphrase, usb);
    expect(a.ok && b.ok, isTrue);
    expect(a.notes, 2);
    expect(b.notes, 0, reason: 'already restored');
    expect(b.generation, 2);
    final owned = await standby.classSyncDao.ownedClasses();
    expect(owned.single.groupUuid, east.groupUuid);
    expect(owned.single.classKey, isNotNull);
    fresh.dispose();
  });
}
