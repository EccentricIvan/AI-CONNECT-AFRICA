import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../db/otic_database.dart';
import '../sync/class_crypto.dart';
import '../sync/device_registry.dart';
import 'admin_records.dart';
import 'admin_records_crypto.dart';

const kAdminRecordsPath = 'api/v4/admin/records';

/// How long a device waits for the Admin to tap Accept.
const kAdminApprovalTimeout = Duration(minutes: 2);

/// A device asking for the school records, waiting for the Admin.
class AdminRecordsRequest {
  AdminRecordsRequest._(this.id, this.name);
  final int id;
  final String name;
  final _decision = Completer<bool>();
}

/// Serves the Admin's school records to another device, one way, while the
/// Admin keeps it open: the device must type the code shown here, and the
/// Admin must tap Accept. The code never crosses the network (a
/// PBKDF2-stretched proof does), the reply is encrypted for that device
/// only, and after 20 wrong tries the code stops working. Anything wrong
/// gets the same bare 404.
class AdminRecordsServer {
  AdminRecordsServer(
    OticDatabase db, {
    this.approvalTimeout = kAdminApprovalTimeout,
    this.kdfRounds = kJoinKdfRounds,
  }) : _records = AdminRecords(db),
       _devices = DeviceRegistry(db);

  final AdminRecords _records;
  final DeviceRegistry _devices;
  final Duration approvalTimeout;
  final int kdfRounds;

  HttpServer? _server;
  String? _code;
  DateTime? _expires;
  int _failures = 0;
  int _nextId = 0;
  Map<String, Object?>? _takeover;
  final _pending = <AdminRecordsRequest>[];
  final _pendingCtl = StreamController<List<AdminRecordsRequest>>.broadcast();

  static const maxFailures = 20;
  static const codeLife = Duration(minutes: 30);

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get code => _code;
  bool get locked => _failures >= maxFailures;
  Stream<List<AdminRecordsRequest>> get pending => _pendingCtl.stream;

  /// Starts serving with a fresh code. [takeover] (from
  /// [sealAdminTakeover]) goes with the records when the Admin wants to be
  /// able to take over on the receiving device.
  Future<int> start({int port = 0, Map<String, Object?>? takeover}) async {
    _takeover = takeover;
    final server = await shelf_io.serve(
      _handle,
      InternetAddress.anyIPv4,
      port,
    );
    _server = server;
    newCode();
    return server.port;
  }

  String newCode() {
    _code = normalizeJoinCode(newJoinCode());
    _expires = DateTime.now().add(codeLife);
    _failures = 0;
    return _code!;
  }

  void decide(AdminRecordsRequest r, {required bool accept}) {
    if (!r._decision.isCompleted) r._decision.complete(accept);
  }

  Future<void> stop() async {
    for (final r in List.of(_pending)) {
      decide(r, accept: false);
    }
    await _server?.close(force: true);
    _server = null;
    _code = null;
  }

  Response _notFound() => Response.notFound('');

  Future<Response> _handle(Request request) async {
    if (request.method != 'POST' || request.url.path != kAdminRecordsPath) {
      return _notFound();
    }
    final code = _code, expires = _expires;
    if (code == null ||
        expires == null ||
        DateTime.now().isAfter(expires) ||
        locked) {
      return _notFound();
    }
    final Object? body;
    try {
      body = jsonDecode(await request.readAsString());
    } catch (_) {
      return _notFound();
    }
    if (body is! Map) return _notFound();
    final salt = body['salt'], proof = body['proof'], name = body['name'];
    if (salt is! String || proof is! String || salt.length < 16) {
      return _notFound();
    }
    final secret = await joinSecret(code, salt, rounds: kdfRounds);
    if (!constantTimeEquals(await joinProof(secret, salt), proof)) {
      _failures++;
      return _notFound();
    }

    final r = AdminRecordsRequest._(
      _nextId++,
      name is String && name.trim().isNotEmpty ? name.trim() : 'A device',
    );
    _pending.add(r);
    _pendingCtl.add(List.unmodifiable(_pending));
    final bool accepted;
    try {
      accepted = await r._decision.future.timeout(
        approvalTimeout,
        onTimeout: () => false,
      );
    } finally {
      _pending.remove(r);
      _pendingCtl.add(List.unmodifiable(_pending));
    }
    if (!accepted) return _notFound();
    // Known to the Admin from now on, so it can be revoked school-wide.
    final deviceKey = body['device_key'];
    if (deviceKey is String && deviceKey.isNotEmpty) {
      await _devices.registerSchoolDevice(deviceKey, r.name);
    }

    final bundle = await _records.export(takeover: _takeover);
    if (bundle == null) return _notFound();
    return Response.ok(
      jsonEncode(await sealJoinBundle(secret, salt, bundle)),
      headers: {'content-type': 'application/json'},
    );
  }

  void dispose() {
    unawaited(stop());
    _pendingCtl.close();
  }
}

/// Asks the Admin's device at [address]:[port] for the school records with
/// the code the Admin shows, and applies them. Null when taken; else why
/// not.
Future<String?> receiveAdminRecords(
  OticDatabase db, {
  required String address,
  required int port,
  required String typedCode,
  String deviceName = '',
  int kdfRounds = kJoinKdfRounds,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final code = normalizeJoinCode(typedCode);
  if (code == null) return 'That isn’t a code — it has 8 letters and numbers';
  final salt = newNonce();
  final secret = await joinSecret(code, salt, rounds: kdfRounds);
  final http.Response reply;
  try {
    reply = await http
        .post(
          Uri.parse('http://$address:$port/$kAdminRecordsPath'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'salt': salt,
            'proof': await joinProof(secret, salt),
            'name': deviceName,
            'device_key': (await DeviceRegistry(db).myKeys())['device_key'],
          }),
        )
        .timeout(timeout);
  } catch (_) {
    return 'Could not reach the Admin’s device';
  }
  if (reply.statusCode != 200) {
    return 'Wrong code, or the Admin didn’t accept';
  }
  final Object? bundle;
  try {
    bundle = await openJoinBundle(secret, salt, jsonDecode(reply.body));
  } catch (_) {
    return 'The records could not be opened';
  }
  return AdminRecords(db).apply(bundle);
}
