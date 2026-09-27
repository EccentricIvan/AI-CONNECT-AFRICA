import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../db/otic_database.dart';
import 'class_crypto.dart';
import 'routing_envelope.dart';

/// Paths of the class-sync protocol. Version 2: version 1 had no access
/// control at all and is not served.
const kJoinPath = 'api/v2/join';
const kHandshakePath = 'api/v2/sync/handshake';
const kChannelPath = 'api/v2/sync/channel';

/// Headers a sync request carries.
const kClassHeader = 'x-otic-class';
const kNonceHeader = 'x-otic-nonce';
const kMacHeader = 'x-otic-mac';

/// Wrong join codes tolerated across all open codes before every code is
/// closed — the teacher then makes a new one.
const kMaxFailedJoins = 20;

class _OpenCode {
  _OpenCode(this.classUuid, this.expires);
  final String classUuid;
  final DateTime expires;
}

/// The embedded HTTP server a teacher's device runs so student devices on
/// the same Wi-Fi/hotspot can pull the class's shared notes.
///
/// Who gets what is enforced here, not by network position:
///
/// * Only classes the teacher is [serving] right now, and only classes this
///   device created — never one it joined.
/// * A request must be MAC'd with the class key and name the class's
///   school. Anything else — unknown class, bad MAC, wrong school — gets the
///   same bare 404, so a guesser learns nothing.
/// * Only notes written on this device and explicitly shared with the class
///   are served (`ClassSyncDao.sharedChunks`).
/// * Replies are encrypted with the class key and signed with this device's
///   key over the requester's nonce (see `class_crypto.dart`).
///
/// A student device gets the class key by typing a join code the teacher
/// opened with [openJoinCode]. The code never crosses the network.
class TeacherSyncServer {
  TeacherSyncServer(this._db, {this.joinRounds = kJoinKdfRounds});

  final OticDatabase _db;

  /// PBKDF2 rounds for join codes — lowered only in tests.
  final int joinRounds;

  HttpServer? _server;
  final Set<String> serving = {};
  final Map<String, _OpenCode> _codes = {};
  int _failedJoins = 0;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Whether too many wrong codes closed every join code.
  bool get joinLocked => _failedJoins >= kMaxFailedJoins;

  Future<int> start({required Set<String> classUuids, int port = 8765}) async {
    serving
      ..clear()
      ..addAll(classUuids);
    if (_server != null) return _server!.port;
    final server = await shelf_io.serve(_route, InternetAddress.anyIPv4, port);
    _server = server;
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _codes.clear();
  }

  /// Opens a new join code for [group] (replacing any earlier one for it)
  /// and returns it for display, `XXXX-XXXX`. Null when the class can't be
  /// joined: not created on this device, or no school set.
  Future<String?> openJoinCode(
    ClassGroup group, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
    if (group.joined || group.groupUuid == null) return null;
    final keyed = await _db.classSyncDao.ensureClassKey(group);
    if (keyed.schoolId == null) return null;
    _codes.removeWhere((_, c) => c.classUuid == group.groupUuid);
    final code = newJoinCode();
    _codes[normalizeJoinCode(code)!] = _OpenCode(
      group.groupUuid!,
      DateTime.now().add(ttl),
    );
    _failedJoins = 0;
    return code;
  }

  void closeJoinCodes() => _codes.clear();

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
    if (_codes.isEmpty || joinLocked) {
      _codes.clear();
      return _notFound();
    }
    final body = jsonDecode(await request.readAsString());
    final salt = body is Map ? body['nonce'] : null;
    final proof = body is Map ? body['proof'] : null;
    if (salt is! String || salt.length < 16 || proof is! String) {
      return _notFound();
    }

    for (final entry in _codes.entries.toList()) {
      final secret = await joinSecret(entry.key, salt, rounds: joinRounds);
      if (!constantTimeEquals(await joinProof(secret, salt), proof)) continue;

      final group = await _db.classSyncDao.ownedByUuid(entry.value.classUuid);
      if (group == null || group.classKey == null || group.schoolId == null) {
        return _notFound();
      }
      final me = await _db.classSyncDao.identity();
      final bundle = await sealJoinBundle(secret, salt, {
        'school_id': group.schoolId,
        'school_name': me.schoolName ?? '',
        'class_group_uuid': group.groupUuid,
        'class_name': group.className,
        'stream_name': group.streamName,
        'class_key': group.classKey,
        'teacher_public_key': await signingPublicKey(me.signingSeed),
      });
      return _json({'bundle': bundle});
    }
    _failedJoins++;
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

    final group = await _db.classSyncDao.ownedByUuid(classUuid);
    final classKey = group?.classKey;
    if (group == null || classKey == null || group.schoolId == null) {
      return _notFound();
    }

    final raw = await request.readAsString();
    final path = request.url.path;
    final expected = await requestMac(
      classKey: classKey,
      path: path,
      nonce: nonce,
      body: raw,
    );
    if (!constantTimeEquals(expected, mac)) return _notFound();

    final body = jsonDecode(raw);
    if (body is! Map || body['school_id'] != group.schoolId) return _notFound();

    final Object reply;
    if (path == kHandshakePath) {
      final subjects = <Map<String, Object?>>[];
      for (final subject in await _db.classSyncDao.sharedSubjects(classUuid)) {
        final chunks = await _envelopes(classUuid, subject);
        subjects.add({
          'subject_id': subject,
          'digest': await channelDigest(chunks.map((e) => e.chunkId)),
        });
      }
      reply = {'class_group_uuid': classUuid, 'subjects': subjects};
    } else {
      final subject = body['subject_id'];
      if (subject is! String || subject.isEmpty) return _notFound();
      final chunks = await _envelopes(classUuid, subject);
      reply = {
        'subject_id': subject,
        'digest': await channelDigest(chunks.map((e) => e.chunkId)),
        'chunks': [for (final e in chunks) e.toJson()],
      };
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

  Future<List<ResourceChunkEnvelope>> _envelopes(
    String classUuid,
    String subjectId,
  ) async {
    final rows = await _db.classSyncDao.sharedChunks(classUuid, subjectId);
    return [
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
  }

  Response _json(Object body) => Response.ok(
    jsonEncode(body),
    headers: const {'content-type': 'application/json'},
  );
}
