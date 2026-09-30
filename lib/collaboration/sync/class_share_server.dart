import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../db/otic_database.dart';
import '../../db/tables/sync_identity_table.dart' show kRoleStudent;
import 'class_crypto.dart';
import 'progress_report.dart';
import 'routing_envelope.dart';

/// Paths of the class-sync protocol. Version 4: a class may have
/// co-teacher devices, each delegated specific subjects and each serving
/// with its own signing key (`api/v4/coteacher/join`); a class's signed,
/// versioned roster of who may sign what travels alongside its manifests.
/// Version 3 added: classmates may pass the teacher's notes on, and every
/// channel carries the teacher's signed version. Earlier versions are not
/// served — an old build's requests to a v4 server simply don't match any
/// route, and vice versa, rather than a v4 device silently deleting notes
/// an old build can't account for.
const kJoinPath = 'api/v4/join';
const kHandshakePath = 'api/v4/sync/handshake';
const kChannelPath = 'api/v4/sync/channel';

/// A co-teacher device joining a class through its root teacher — grants
/// signing authority for the subjects the root allocates, not just read
/// access, so it gets its own code/TTL/approval flow separate from a
/// student's.
const kCoTeacherJoinPath = 'api/v4/coteacher/join';

/// A student device reporting its learners' progress to the teacher.
const kReportPath = 'api/v4/report';

/// Most learners one device may report at once — a shared classroom
/// device, not a whole school.
const kMaxReportsPerDevice = 60;

/// The port a sharing device listens on unless it is busy — also what a
/// student device assumes when an address is typed without one.
const kDefaultSyncPort = 8765;

/// Headers a sync request carries.
const kClassHeader = 'x-otic-class';
const kNonceHeader = 'x-otic-nonce';
const kMacHeader = 'x-otic-mac';

/// Wrong join codes tolerated from one device (address) before that device
/// is shut out until the sharer makes a new code.
///
/// Per device, not per server: a student's device tries its code on every
/// sharer it can see, so with two teachers — or several students sharing —
/// in one room, every other sharer's joins would otherwise count as wrong
/// guesses here and lock this sharer's whole class out mid-lesson. Guessing
/// stays pointless either way: a right code still needs the sharer's Accept.
const kMaxFailedJoins = 20;

/// How long a join waits for the sharer to tap Accept.
const kJoinApprovalTimeout = Duration(minutes: 2);

/// Default lifetime of a co-teacher invite code — shorter than a student's
/// (30 min), reflecting that it grants signing authority, not just read
/// access.
const kCoTeacherInviteTtl = Duration(minutes: 15);

/// Who is sharing.
enum ShareRole {
  /// A teacher device, serving notes of classes it created.
  teacher,

  /// A student device passing on the teacher's notes it received, to
  /// classmates who already joined the class through the teacher.
  classmate,
}

/// What kind of request is waiting for the sharer's Accept/Decline.
enum PendingJoinKind { student, coTeacher }

/// Someone who typed the right code and is waiting for the sharer's answer.
class PendingJoin {
  const PendingJoin({
    required this.id,
    required this.name,
    required this.address,
    required this.classUuid,
    this.kind = PendingJoinKind.student,
    this.subjectIds = const [],
  });

  final String id;

  /// The learner's (or co-teacher's) name as their device sent it.
  /// Informational — the code is what proved they were given it.
  final String name;
  final String address;
  final String classUuid;
  final PendingJoinKind kind;

  /// [PendingJoinKind.coTeacher] only: the subjects this invite would
  /// allocate, so the approval UI can show what's being granted.
  final List<String> subjectIds;
}

class _OpenCode {
  _OpenCode(this.classUuid, this.expires, {this.subjectIds = const []});
  final String classUuid;
  final DateTime expires;

  /// Co-teacher codes only.
  final List<String> subjectIds;
}

class _Waiting {
  _Waiting(this.info);
  final PendingJoin info;
  final decision = Completer<bool>();
}

/// What this device knows about a class it's asked to sync, whichever of
/// `ClassGroups` (owned or joined) or `CoTeachingClasses` (delegated) it
/// came from — see [ClassShareServer._resolveServedClass].
class _ServedClass {
  const _ServedClass({
    required this.groupUuid,
    required this.schoolId,
    required this.classKey,
    required this.allocatedSubjects,
    this.rosterJson,
  });

  final String groupUuid;
  final String? schoolId;
  final String? classKey;

  /// Null for root (or a classmate, which has no allocation concept) —
  /// unrestricted. Non-null for a co-teacher device: only these subjects
  /// may ever be served or signed for.
  final Set<String>? allocatedSubjects;

  /// The class's signed co-teacher roster (JSON), forwarded verbatim —
  /// null if the class has never had a co-teacher.
  final String? rosterJson;

  bool get isDelegate => allocatedSubjects != null;
}

/// The embedded HTTP server a sharing device runs so other devices on the
/// same Wi-Fi/hotspot can pull a class's notes.
///
/// Who gets what is enforced here, not by network position:
///
/// * **Joining takes the right code and the sharer's Accept.** A device
///   proves it knows the code (the code never crosses the network), then
///   waits while the sharer sees its name and taps Accept or Decline.
/// * **Teacher role:** only classes this device created, only notes it
///   wrote and explicitly shared with the class (`ClassSyncDao.sharedChunks`).
///   Replies are signed with the teacher key over the requester's nonce, and
///   each channel carries a signed, monotonic manifest.
/// * **Classmate role:** only the one class this device joined through the
///   teacher, only the notes it received, verbatim, with the teacher's
///   manifests — so the next device can check they are the teacher's and
///   newer than what it holds. Only devices this classmate accepted may
///   pull: their requests are MAC'd with the session token handed over at
///   join, not just the class key.
/// * Anything else — unknown class, bad MAC, wrong school, no session —
///   gets the same bare 404, so a guesser learns nothing.
class ClassShareServer {
  ClassShareServer(
    this._db, {
    this.role = ShareRole.teacher,
    this.joinRounds = kJoinKdfRounds,
    this.approvalTimeout = kJoinApprovalTimeout,
  });

  final OticDatabase _db;
  final ShareRole role;

  /// PBKDF2 rounds for join codes — lowered only in tests.
  final int joinRounds;
  final Duration approvalTimeout;

  HttpServer? _server;
  final Set<String> serving = {};
  final Map<String, _OpenCode> _codes = {};

  /// Separate from [_codes]: a co-teacher code grants signing authority,
  /// not just read access, so it isn't spent by — or counted against —
  /// ordinary student join guessing.
  final Map<String, _OpenCode> _coTeacherCodes = {};
  final Map<String, int> _failedJoins = {};

  final Map<String, _Waiting> _waiting = {};
  final _pendingCtrl = StreamController<List<PendingJoin>>.broadcast();

  /// Classmate role: tokens of devices the sharer accepted.
  final Set<String> _sessions = {};

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Whether some device was shut out for too many wrong codes.
  bool get joinLocked => _failedJoins.values.any((n) => n >= kMaxFailedJoins);

  bool _lockedOut(String address) =>
      (_failedJoins[address] ?? 0) >= kMaxFailedJoins;

  static String _remote(Request request) {
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : '';
  }

  /// Joins waiting for the sharer's Accept or Decline, oldest first.
  List<PendingJoin> get pendingJoins => [
    for (final w in _waiting.values) w.info,
  ];

  /// Emits [pendingJoins] every time it changes.
  Stream<List<PendingJoin>> get pendingJoinsStream => _pendingCtrl.stream;

  /// The sharer's answer to one waiting join.
  void decide(String id, {required bool accept}) {
    final w = _waiting.remove(id);
    if (w == null) return;
    if (!w.decision.isCompleted) w.decision.complete(accept);
    _emitPending();
  }

  /// Starts serving [classUuids]. Tries [port], then any free port — a
  /// device can be sharing as teacher and as classmate at once.
  Future<int> start({
    required Set<String> classUuids,
    int port = kDefaultSyncPort,
  }) async {
    serving
      ..clear()
      ..addAll(classUuids);
    if (_server != null) return _server!.port;
    HttpServer server;
    try {
      server = await shelf_io.serve(_route, InternetAddress.anyIPv4, port);
    } on SocketException {
      if (port == 0) rethrow;
      server = await shelf_io.serve(_route, InternetAddress.anyIPv4, 0);
    }
    _server = server;
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _codes.clear();
    _coTeacherCodes.clear();
    _sessions.clear();
    for (final w in _waiting.values) {
      if (!w.decision.isCompleted) w.decision.complete(false);
    }
    _waiting.clear();
    _emitPending();
  }

  void dispose() {
    unawaited(stop());
    _pendingCtrl.close();
  }

  /// Opens a new join code for [group] (replacing any earlier one for it)
  /// and returns it for display, `XXXX-XXXX`. Null when this device can't
  /// share the class in its role: as teacher, a class it created; as
  /// classmate, a class it joined through the teacher.
  Future<String?> openJoinCode(
    ClassGroup group, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
    final uuid = group.groupUuid;
    if (uuid == null) return null;
    final ClassGroup? usable;
    if (role == ShareRole.teacher) {
      // A student device never shares as a teacher, whatever it owns.
      if (group.joined ||
          await _db.classSyncDao.deviceRole() == kRoleStudent) {
        return null;
      }
      final keyed = await _db.classSyncDao.ensureClassKey(group);
      usable = keyed.schoolId == null ? null : keyed;
    } else {
      usable = await _joinedClass(uuid);
    }
    if (usable == null) return null;
    _codes.removeWhere((_, c) => c.classUuid == uuid);
    final code = newJoinCode();
    _codes[normalizeJoinCode(code)!] = _OpenCode(
      uuid,
      DateTime.now().add(ttl),
    );
    _failedJoins.clear();
    return code;
  }

  void closeJoinCodes() => _codes.clear();

  /// Opens a new co-teacher invite code for [group], allocating [subjectIds]
  /// on accept. Null when this device can't invite a co-teacher (a student
  /// device, or a class it doesn't own — only root ever invites), or when
  /// any of [subjectIds] is already allocated to another co-teacher of this
  /// class (re-checked here against a race with another invite flow, not
  /// just at the picker).
  Future<String?> openCoTeacherInviteCode(
    ClassGroup group, {
    required List<String> subjectIds,
    Duration ttl = kCoTeacherInviteTtl,
  }) async {
    final uuid = group.groupUuid;
    if (uuid == null ||
        role != ShareRole.teacher ||
        group.joined ||
        await _db.classSyncDao.deviceRole() == kRoleStudent) {
      return null;
    }
    final keyed = await _db.classSyncDao.ensureClassKey(group);
    if (keyed.schoolId == null) return null;
    final already = await _db.coTeacherDao.allocatedSubjects(uuid);
    if (subjectIds.any(already.contains)) return null;
    _coTeacherCodes.removeWhere((_, c) => c.classUuid == uuid);
    final code = newJoinCode();
    _coTeacherCodes[normalizeJoinCode(code)!] = _OpenCode(
      uuid,
      DateTime.now().add(ttl),
      subjectIds: subjectIds,
    );
    return code;
  }

  void _emitPending() {
    if (!_pendingCtrl.isClosed) _pendingCtrl.add(pendingJoins);
  }

  /// The class this device serves in its role, by uuid — used only for
  /// resolving a student/classmate join code, which only ever names a class
  /// this device fully owns (root) or fully joined, never a delegated one
  /// (co-teachers can't issue student codes; see [openCoTeacherInviteCode]
  /// vs [openJoinCode]).
  Future<ClassGroup?> _servedClass(String uuid) =>
      role == ShareRole.teacher
          ? _db.classSyncDao.ownedByUuid(uuid)
          : _joinedClass(uuid);

  Future<ClassGroup?> _joinedClass(String uuid) =>
      _db.classSyncDao.joinedByUuid(uuid);

  /// What this device knows about the class it's asked to sync, whichever
  /// of `ClassGroups` (owned or joined) or `CoTeachingClasses` (delegated)
  /// it came from — used by [_sync]'s handshake/channel/report dispatch,
  /// unlike [_servedClass] which only ever resolves a fully-owned or
  /// fully-joined class for the join flow above.
  Future<_ServedClass?> _resolveServedClass(String uuid) async {
    if (role == ShareRole.classmate) {
      final g = await _joinedClass(uuid);
      if (g == null) return null;
      return _ServedClass(
        groupUuid: uuid,
        schoolId: g.schoolId,
        classKey: g.classKey,
        allocatedSubjects: null,
      );
    }
    final owned = await _db.classSyncDao.ownedByUuid(uuid);
    if (owned != null) {
      return _ServedClass(
        groupUuid: uuid,
        schoolId: owned.schoolId,
        classKey: owned.classKey,
        allocatedSubjects: null,
        rosterJson: owned.rosterJson,
      );
    }
    final delegated = await _db.coTeacherDao.delegatedByUuid(uuid);
    if (delegated == null) return null;
    return _ServedClass(
      groupUuid: uuid,
      schoolId: delegated.schoolId,
      classKey: delegated.classKey,
      allocatedSubjects: {
        for (final s in jsonDecode(delegated.subjectIdsJson) as List)
          if (s is String) s,
      },
      rosterJson: delegated.rosterJson,
    );
  }

  // ── Routing ─────────────────────────────────────────────────────────────

  // A fresh response each time: a shelf Response's body can only be read once.
  static Response _notFound() => Response.notFound(
    '',
    headers: const {'content-type': 'application/json'},
  );

  Future<Response> _route(Request request) async {
    if (request.method != 'POST') return _notFound();
    try {
      return switch (request.url.path) {
        kJoinPath => await _join(request),
        kCoTeacherJoinPath when role == ShareRole.teacher =>
          await _coTeacherJoin(request),
        kHandshakePath || kChannelPath => await _sync(request),
        kReportPath when role == ShareRole.teacher => await _sync(request),
        _ => _notFound(),
      };
    } catch (_) {
      return _notFound();
    }
  }

  // ── Join ────────────────────────────────────────────────────────────────

  Future<Response> _join(Request request) async {
    final now = DateTime.now();
    _codes.removeWhere((_, c) => c.expires.isBefore(now));
    final from = _remote(request);
    if (_codes.isEmpty || _lockedOut(from)) return _notFound();
    final body = jsonDecode(await request.readAsString());
    final salt = body is Map ? body['nonce'] : null;
    final proof = body is Map ? body['proof'] : null;
    final rawName = body is Map ? body['name'] : null;
    if (salt is! String || salt.length < 16 || proof is! String) {
      return _notFound();
    }

    for (final entry in _codes.entries.toList()) {
      final secret = await joinSecret(entry.key, salt, rounds: joinRounds);
      if (!constantTimeEquals(await joinProof(secret, salt), proof)) continue;

      final group = await _servedClass(entry.value.classUuid);
      if (group == null || group.classKey == null || group.schoolId == null) {
        return _notFound();
      }

      // The right code — now the sharer decides.
      if (!await _approve(request, rawName, group.groupUuid!)) {
        return _notFound();
      }

      final me = await _db.classSyncDao.identity();
      final Map<String, Object?> details;
      if (role == ShareRole.teacher) {
        details = {
          'school_id': group.schoolId,
          'school_name': me.schoolName ?? '',
          'class_group_uuid': group.groupUuid,
          'class_name': group.className,
          'stream_name': group.streamName,
          'class_key': group.classKey,
          'teacher_public_key': await signingPublicKey(me.signingSeed),
          // So a brand-new student already has a cached roster before its
          // first sync, even one against a co-teacher's device — see
          // SelectiveSyncManager's bootstrap handling.
          if (group.rosterJson != null) 'roster': jsonDecode(group.rosterJson!),
        };
      } else {
        final token = newSessionToken();
        _sessions.add(token);
        details = {
          'school_id': group.schoolId,
          'class_group_uuid': group.groupUuid,
          'session_token': token,
        };
      }
      return _json({'bundle': await sealJoinBundle(secret, salt, details)});
    }
    _failedJoins[from] = (_failedJoins[from] ?? 0) + 1;
    return _notFound();
  }

  Future<bool> _approve(
    Request request,
    Object? rawName,
    String classUuid, {
    PendingJoinKind kind = PendingJoinKind.student,
    List<String> subjectIds = const [],
  }) async {
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim().substring(0, rawName.trim().length.clamp(0, 40))
        : (kind == PendingJoinKind.coTeacher ? 'A teacher' : 'A learner');
    final waiting = _Waiting(
      PendingJoin(
        id: newNonce(),
        name: name,
        address: _remote(request),
        classUuid: classUuid,
        kind: kind,
        subjectIds: subjectIds,
      ),
    );
    _waiting[waiting.info.id] = waiting;
    _emitPending();
    final accepted = await waiting.decision.future.timeout(
      approvalTimeout,
      onTimeout: () => false,
    );
    if (_waiting.remove(waiting.info.id) != null) _emitPending();
    return accepted && _server != null;
  }

  // ── Co-teacher join ─────────────────────────────────────────────────────

  Future<Response> _coTeacherJoin(Request request) async {
    final now = DateTime.now();
    _coTeacherCodes.removeWhere((_, c) => c.expires.isBefore(now));
    final from = _remote(request);
    if (_coTeacherCodes.isEmpty || _lockedOut(from)) return _notFound();
    final body = jsonDecode(await request.readAsString());
    final salt = body is Map ? body['nonce'] : null;
    final proof = body is Map ? body['proof'] : null;
    final rawName = body is Map ? body['name'] : null;
    final devicePublicKey = body is Map ? body['device_public_key'] : null;
    if (salt is! String ||
        salt.length < 16 ||
        proof is! String ||
        devicePublicKey is! String ||
        devicePublicKey.isEmpty) {
      return _notFound();
    }

    for (final entry in _coTeacherCodes.entries.toList()) {
      final secret = await joinSecret(entry.key, salt, rounds: joinRounds);
      final expected = await coTeacherJoinProof(secret, salt, devicePublicKey);
      if (!constantTimeEquals(expected, proof)) continue;

      final group = await _db.classSyncDao.ownedByUuid(entry.value.classUuid);
      if (group == null || group.classKey == null || group.schoolId == null) {
        return _notFound();
      }

      if (!await _approve(
        request,
        rawName,
        group.groupUuid!,
        kind: PendingJoinKind.coTeacher,
        subjectIds: entry.value.subjectIds,
      )) {
        return _notFound();
      }

      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim().substring(0, rawName.trim().length.clamp(0, 40))
          : 'A teacher';
      final added = await _db.coTeacherDao.addCoTeacher(
        group: group,
        publicKey: devicePublicKey,
        name: name,
        subjectIds: entry.value.subjectIds,
      );
      if (!added) return _notFound();
      // Re-read: addCoTeacher just bumped rosterVersion/rosterJson.
      final updated = await _db.classSyncDao.ownedByUuid(group.groupUuid!);
      if (updated?.rosterJson == null) return _notFound();

      final me = await _db.classSyncDao.identity();
      final details = {
        'school_id': updated!.schoolId,
        'school_name': me.schoolName ?? '',
        'class_group_uuid': updated.groupUuid,
        'class_name': updated.className,
        'stream_name': updated.streamName,
        'class_key': updated.classKey,
        'root_public_key': await signingPublicKey(me.signingSeed),
        'subject_ids': entry.value.subjectIds,
        'roster': jsonDecode(updated.rosterJson!),
      };
      _coTeacherCodes.remove(entry.key);
      return _json({'bundle': await sealJoinBundle(secret, salt, details)});
    }
    _failedJoins[from] = (_failedJoins[from] ?? 0) + 1;
    return _notFound();
  }

  // ── Sync ────────────────────────────────────────────────────────────────

  Future<Response> _sync(Request request) async {
    final classUuid = request.headers[kClassHeader];
    final nonce = request.headers[kNonceHeader];
    final mac = request.headers[kMacHeader];
    if (classUuid == null ||
        nonce == null ||
        nonce.length < 16 ||
        mac == null) {
      return _notFound();
    }
    if (!serving.contains(classUuid)) return _notFound();

    final served = await _resolveServedClass(classUuid);
    final classKey = served?.classKey;
    if (served == null || classKey == null || served.schoolId == null) {
      return _notFound();
    }

    final raw = await request.readAsString();
    final path = request.url.path;
    if (!await _macOk(classKey, path, nonce, raw, mac)) return _notFound();

    final body = jsonDecode(raw);
    if (body is! Map || body['school_id'] != served.schoolId) {
      return _notFound();
    }

    final Object? reply = switch (path) {
      kHandshakePath => await _handshake(served),
      // A co-teacher device never receives progress reports — root only.
      kReportPath when !served.isDelegate =>
        await _report(served, classKey, nonce, body['report']),
      kReportPath => null,
      _ => await _channel(served, body['subject_id']),
    };
    if (reply == null) return _notFound();

    if (role == ShareRole.classmate) {
      return _json(
        await sealRelayReply(
          classKey: classKey,
          requestNonce: nonce,
          json: reply,
        ),
      );
    }
    final me = await _db.classSyncDao.identity();
    return _json(
      await sealReply(
        classKey: classKey,
        signingSeed: me.signingSeed,
        requestNonce: nonce,
        json: reply,
      ),
    );
  }

  /// Teacher: MAC'd with the class key. Classmate: MAC'd with the session
  /// token of a device this classmate accepted — the class key alone is
  /// not enough to pull from a classmate.
  Future<bool> _macOk(
    String classKey,
    String path,
    String nonce,
    String body,
    String mac,
  ) async {
    final keys = role == ShareRole.teacher ? [classKey] : _sessions.toList();
    var ok = false;
    for (final key in keys) {
      final expected = await requestMac(
        classKey: key,
        path: path,
        nonce: nonce,
        body: body,
      );
      if (constantTimeEquals(expected, mac)) ok = true;
    }
    return ok;
  }

  Future<Map<String, Object?>> _handshake(_ServedClass served) async {
    final uuid = served.groupUuid;
    final dao = _db.classSyncDao;
    final manifests = <Map<String, Object?>>[];
    if (role == ShareRole.teacher) {
      final me = await dao.identity();
      var subjects = await dao.sharedSubjects(uuid);
      if (served.allocatedSubjects != null) {
        // A co-teacher: never more than its own allocation, even if a
        // stale share row somehow named a subject outside it.
        subjects = subjects.where(served.allocatedSubjects!.contains).toList();
      } else {
        // Root: never re-offer a subject currently delegated to a
        // co-teacher — that device signs for it now.
        final delegated = await _db.coTeacherDao.allocatedSubjects(uuid);
        subjects = subjects.where((s) => !delegated.contains(s)).toList();
      }
      await dao.retireUnshared(uuid, subjects.toSet());
      for (final subject in subjects) {
        final chunks = await _envelopes(
          uuid,
          await dao.sharedChunks(uuid, subject),
        );
        final digest = await channelDigest(chunks.map((e) => e.chunkId));
        final version = await dao.servedVersion(uuid, subject, digest);
        manifests.add(
          ChannelManifest(
            schoolId: served.schoolId!,
            classUuid: uuid,
            subjectId: subject,
            digest: digest,
            version: version,
            signature: await signManifest(
              signingSeed: me.signingSeed,
              schoolId: served.schoolId!,
              classUuid: uuid,
              subjectId: subject,
              digest: digest,
              version: version,
            ),
          ).toJson(),
        );
      }
    } else {
      // Exactly what the teacher (or co-teacher) signed — never re-signed,
      // never edited.
      for (final s in await dao.relayableChannels(uuid)) {
        manifests.add({
          'subject_id': s.subjectId,
          'digest': s.channelDigest,
          'version': s.channelVersion,
          'sig': s.manifestSig,
        });
      }
    }
    return {
      'class_group_uuid': uuid,
      'subjects': manifests,
      // The subjects this teacher made, so students can see and enroll in
      // them. Only in root's own (signed) reply — never a co-teacher's or
      // a classmate's.
      if (role == ShareRole.teacher && !served.isDelegate)
        'catalog': [
          for (final s in await dao.ownSubjects())
            {'id': s.subjectId, 'name': s.name, 'icon': s.icon, 'color': s.color},
        ],
      // Forwarded verbatim, whichever device this reply comes from — its
      // own signature is what makes it trustworthy, not who's relaying it.
      if (served.rosterJson != null) 'roster': jsonDecode(served.rosterJson!),
    };
  }

  /// Root only: stores the members' progress a student device sent. Never
  /// reached for a delegated class — [_sync] refuses [kReportPath] first.
  Future<Map<String, Object?>?> _report(
    _ServedClass served,
    String classKey,
    String nonce,
    Object? sealed,
  ) async {
    final opened = await openReport(
      classKey: classKey,
      requestNonce: nonce,
      sealed: sealed,
    );
    if (opened is! List) return null;
    final reports = [
      for (final r in opened.take(kMaxReportsPerDevice))
        if (ProgressReport.fromJson(r) case final report?) report,
    ];
    await _db.classSyncDao.saveMemberReports(served.groupUuid, reports);
    return {'saved': reports.length};
  }

  Future<Map<String, Object?>?> _channel(
    _ServedClass served,
    Object? subject,
  ) async {
    if (subject is! String || subject.isEmpty) return null;
    if (served.allocatedSubjects != null &&
        !served.allocatedSubjects!.contains(subject)) {
      // Defense in depth: sharedChunks already returns nothing for a
      // subject this device never wrote/shared, but a delegate must never
      // serve a subject outside its allocation even if that changed.
      return null;
    }
    final uuid = served.groupUuid;
    final rows = role == ShareRole.teacher
        ? await _db.classSyncDao.sharedChunks(uuid, subject)
        : await _db.classSyncDao.receivedChunks(uuid, subject);
    final chunks = await _envelopes(uuid, rows);
    return {
      'subject_id': subject,
      'digest': await channelDigest(chunks.map((e) => e.chunkId)),
      'chunks': [for (final e in chunks) e.toJson()],
    };
  }

  /// Envelopes for [rows]. A received row stores exactly the payload the
  /// teacher sent, so a classmate's envelope hashes to the teacher's
  /// chunk id — which is what lets the next device check it.
  Future<List<ResourceChunkEnvelope>> _envelopes(
    String classUuid,
    List<TopicResource> rows,
  ) async => [
    for (final r in rows)
      ResourceChunkEnvelope.forChannel(
        classGroupUuid: classUuid,
        subjectId: r.subjectId,
        topicKey: r.topicKey,
        termMarker: r.termMarker,
        resourceTitle: r.resourceTitle,
        contentChunk: r.contentChunk,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        documentTitle: r.documentTitle,
      ),
  ];

  Response _json(Object body) => Response.ok(
    jsonEncode(body),
    headers: const {'content-type': 'application/json'},
  );
}
