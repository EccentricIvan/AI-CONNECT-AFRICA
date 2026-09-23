import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../db/otic_database.dart';
import 'routing_envelope.dart';

/// Earliest timestamp a `since` filter can mean — "everything", when a
/// student's device has no prior sync for a channel.
final _epoch = DateTime.utc(1970).toIso8601String();

/// Embedded HTTP server run on a teacher's device, serving class/stream/
/// subject-scoped `topic_resources` to students on the same local network.
///
/// LAN-only by design, matching the trust model [LanDiscoveryService]
/// already uses for presence: this binds to every interface
/// ([InternetAddress.anyIPv4]) so it is reachable from other devices on the
/// same Wi-Fi/hotspot, but it is never announced or reachable outside that
/// network — there is no port-forwarding, no auth token, no TLS. Anyone who
/// can join the classroom's Wi-Fi can read its scoped resources; the app has
/// no internet path in or out at all, which is the actual security boundary
/// here, not this server. Do not expose this port beyond a school LAN.
class TeacherSyncServer {
  TeacherSyncServer(this._db);

  final OticDatabase _db;
  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<int> start({int port = 8765}) async {
    if (_server != null) return _server!.port;
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_route);
    final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _server = server;
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _route(Request request) async {
    if (request.method != 'POST') {
      return _json(405, {'error': 'method not allowed'});
    }
    try {
      switch (request.url.path) {
        case 'api/v1/sync/handshake':
          return await _handshake(request);
        case 'api/v1/sync/channel':
          return await _channel(request);
        default:
          return _json(404, {'error': 'unknown endpoint'});
      }
    } on FormatException catch (e) {
      return _json(400, {'error': 'malformed request: ${e.message}'});
    } catch (e) {
      return _json(500, {'error': 'server error'});
    }
  }

  /// `POST /api/v1/sync/handshake` — `{"class_group_uuid": "..."}` →
  /// `{"class_group_uuid", "subjects": [{"subject_id", "version"}, ...]}`.
  ///
  /// Validates the class/stream is one this device actually knows before
  /// answering anything — a student device pointed at the wrong teacher (or
  /// with a stale/mistyped class id) gets a clean 404, not an empty-but-200
  /// answer that looks like "this class has no material yet".
  Future<Response> _handshake(Request request) async {
    final body = await _readJsonObject(request);
    final classGroupUuid = _requireString(body, 'class_group_uuid');

    final group = await _db.classGroupDao.findByUuid(classGroupUuid);
    if (group == null) {
      return _json(404, {'error': 'unknown class_group_uuid'});
    }

    final subjects = await _db.topicResourceDao.subjectVersionsForClass(
      classGroupUuid,
    );
    return _json(200, {
      'class_group_uuid': classGroupUuid,
      'subjects': [
        for (final s in subjects) {'subject_id': s.subjectId, 'version': s.version},
      ],
    });
  }

  /// `POST /api/v1/sync/channel` —
  /// `{"class_group_uuid", "subject_id", "since"?}` →
  /// `{"chunks": [ResourceChunkEnvelope, ...]}`.
  ///
  /// `since` is optional; omitted or null means "every chunk on this
  /// channel" (a student's first sync).
  Future<Response> _channel(Request request) async {
    final body = await _readJsonObject(request);
    final classGroupUuid = _requireString(body, 'class_group_uuid');
    final subjectId = _requireString(body, 'subject_id');
    final since = body['since'];
    final sinceIso = since is String && since.isNotEmpty ? since : _epoch;

    final group = await _db.classGroupDao.findByUuid(classGroupUuid);
    if (group == null) {
      return _json(404, {'error': 'unknown class_group_uuid'});
    }

    final rows = await _db.topicResourceDao.channelChunks(
      classGroupUuid: classGroupUuid,
      subjectId: subjectId,
      sinceIso: sinceIso,
    );
    final envelopes = rows.map((r) => ResourceChunkEnvelope.forChannel(
          classGroupUuid: classGroupUuid,
          subjectId: r.subjectId,
          topicKey: r.topicKey,
          termMarker: r.termMarker,
          resourceTitle: r.resourceTitle,
          contentChunk: r.contentChunk,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
        ));
    return _json(200, {
      'chunks': [for (final e in envelopes) e.toJson()],
    });
  }

  Future<Map<String, Object?>> _readJsonObject(Request request) async {
    final raw = await request.readAsString();
    final decoded = raw.isEmpty ? null : jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('request body must be a JSON object');
    }
    return Map<String, Object?>.from(decoded);
  }

  String _requireString(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('missing or empty "$key"');
    }
    return value;
  }

  Response _json(int status, Map<String, Object?> body) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json'},
      );
}
