import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../db/otic_database.dart';
import 'class_crypto.dart';
import 'progress_report.dart';
import 'routing_envelope.dart';

/// Paths of the class-sync protocol. Version 3: classmates may pass the
/// teacher's notes on, and every channel carries the teacher's signed
/// version. Earlier versions are not served.
const kJoinPath = 'api/v3/join';
const kHandshakePath = 'api/v3/sync/handshake';
const kChannelPath = 'api/v3/sync/channel';

/// A student device reporting its learners' progress to the teacher.
const kReportPath = 'api/v3/report';

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

/// Who is sharing.
enum ShareRole {
  /// A teacher device, serving notes of classes it created.
  teacher,

  /// A student device passing on the teacher's notes it received, to
  /// classmates who already joined the class through the teacher.
  classmate,
}

/// Someone who typed the right code and is waiting for the sharer's answer.
class PendingJoin {
  const PendingJoin({
    required this.id,
    required this.name,
    required this.address,
    required this.classUuid,
  });

  final String id;

  /// The learner's name as their device sent it. Informational — the code
  /// is what proved they were given it.
  final String name;
  final String address;
  final String classUuid;
}

class _OpenCode {
  _OpenCode(this.classUuid, this.expires);
  final String classUuid;
  final DateTime expires;
}

class _Waiting {
  _Waiting(this.info);
  final PendingJoin info;
  final decision = Completer<bool>();
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
      if (group.joined) return null;
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

  void _emitPending() {
    if (!_pendingCtrl.isClosed) _pendingCtrl.add(pendingJoins);
  }

  /// The class this device serves in its role, by uuid.
  Future<ClassGroup?> _servedClass(String uuid) =>
      role == ShareRole.teacher
          ? _db.classSyncDao.ownedByUuid(uuid)
          : _joinedClass(uuid);

  Future<ClassGroup?> _joinedClass(String uuid) =>
      _db.classSyncDao.joinedByUuid(uuid);

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
    String classUuid,
  ) async {
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim().substring(0, rawName.trim().length.clamp(0, 40))
        : 'A learner';
    final waiting = _Waiting(
      PendingJoin(
        id: newNonce(),
        name: name,
        address: _remote(request),
        classUuid: classUuid,
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

    final group = await _servedClass(classUuid);
    final classKey = group?.classKey;
    if (group == null || classKey == null || group.schoolId == null) {
      return _notFound();
    }

    final raw = await request.readAsString();
    final path = request.url.path;
    if (!await _macOk(classKey, path, nonce, raw, mac)) return _notFound();

    final body = jsonDecode(raw);
    if (body is! Map || body['school_id'] != group.schoolId) return _notFound();

    final Object? reply = switch (path) {
      kHandshakePath => await _handshake(group),
      kReportPath => await _report(group, classKey, nonce, body['report']),
      _ => await _channel(group, body['subject_id']),
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

  Future<Map<String, Object?>> _handshake(ClassGroup group) async {
    final uuid = group.groupUuid!;
    final dao = _db.classSyncDao;
    final manifests = <Map<String, Object?>>[];
    if (role == ShareRole.teacher) {
      final me = await dao.identity();
      final subjects = await dao.sharedSubjects(uuid);
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
            schoolId: group.schoolId!,
            classUuid: uuid,
            subjectId: subject,
            digest: digest,
            version: version,
            signature: await signManifest(
              signingSeed: me.signingSeed,
              schoolId: group.schoolId!,
              classUuid: uuid,
              subjectId: subject,
              digest: digest,
              version: version,
            ),
          ).toJson(),
        );
      }
    } else {
      // Exactly what the teacher signed — never re-signed, never edited.
      for (final s in await dao.relayableChannels(uuid)) {
        manifests.add({
          'subject_id': s.subjectId,
          'digest': s.channelDigest,
          'version': s.channelVersion,
          'sig': s.manifestSig,
        });
      }
    }
    return {'class_group_uuid': uuid, 'subjects': manifests};
  }

  /// Teacher only: stores the members' progress a student device sent.
  Future<Map<String, Object?>?> _report(
    ClassGroup group,
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
    await _db.classSyncDao.saveMemberReports(group.groupUuid!, reports);
    return {'saved': reports.length};
  }

  Future<Map<String, Object?>?> _channel(
    ClassGroup group,
    Object? subject,
  ) async {
    if (subject is! String || subject.isEmpty) return null;
    final uuid = group.groupUuid!;
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
