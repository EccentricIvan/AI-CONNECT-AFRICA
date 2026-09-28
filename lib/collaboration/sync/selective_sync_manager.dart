import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../../db/otic_database.dart';
import 'class_crypto.dart';
import 'class_share_server.dart'
    show
        kChannelPath,
        kClassHeader,
        kHandshakePath,
        kJoinApprovalTimeout,
        kJoinPath,
        kMacHeader,
        kNonceHeader,
        kReportPath;
import 'progress_report.dart';
import 'routing_envelope.dart';

/// One malformed or mismatched block, kept for a post-sync report rather
/// than only a running count.
class RejectedChunk {
  const RejectedChunk({required this.reason, this.routingKey});
  final String reason;
  final String? routingKey;
}

/// What one sync run actually did.
class SyncResult {
  const SyncResult({
    required this.subjectsChecked,
    required this.subjectsUpdated,
    required this.chunksInserted,
    required this.rejected,
    this.subjectsRemoved = 0,
    this.learnersReported = 0,
    this.error,
  });

  /// Learners on this device whose progress the teacher received.
  final int learnersReported;

  final int subjectsChecked;
  final int subjectsUpdated;
  final int chunksInserted;
  final int subjectsRemoved;
  final List<RejectedChunk> rejected;

  /// Set only when the whole run failed before touching any subject.
  final String? error;

  bool get ok => error == null;

  static SyncResult failed(String error) => SyncResult(
    subjectsChecked: 0,
    subjectsUpdated: 0,
    chunksInserted: 0,
    rejected: const [],
    error: error,
  );
}

/// A sharing device seen on the network (or typed in).
typedef TeacherEndpoint = ({String address, int port});

/// Outcome of typing a teacher's join code.
class JoinResult {
  const JoinResult.joined(ClassGroup this.group, this.schoolName)
    : error = null;
  const JoinResult.failed(String this.error) : group = null, schoolName = null;

  final ClassGroup? group;
  final String? schoolName;
  final String? error;
  bool get ok => group != null;
}

/// Access a classmate granted this device: their address, the class, and
/// the session token that lets this device pull from them. Held in memory
/// only — it ends when either device stops.
class ClassmateSession {
  const ClassmateSession({
    required this.endpoint,
    required this.group,
    required this.token,
  });
  final TeacherEndpoint endpoint;
  final ClassGroup group;
  final String token;
}

/// Outcome of typing a classmate's code.
class ClassmateJoinResult {
  const ClassmateJoinResult.joined(ClassmateSession this.session)
    : error = null;
  const ClassmateJoinResult.failed(String this.error) : session = null;
  final ClassmateSession? session;
  final String? error;
  bool get ok => session != null;
}

/// A student device's side of class sync: joining a class with the
/// teacher's code, pulling that class's notes from the teacher, and pulling
/// them from a classmate who is passing them on.
///
/// Each subject is replaced as a whole, in one transaction, and only when
/// every chunk checks out — a teacher's edits and removals arrive exactly,
/// and a bad reply never leaves half a subject behind. A failing subject
/// never stops the next one.
///
/// Every subject comes with the teacher's signed manifest (digest +
/// version). From a classmate, a subject is taken only if that signature
/// checks against the teacher key pinned at join and its version is newer
/// than this device's — a classmate can pass notes on, but can't edit,
/// invent, remove or roll back any of them.
class SelectiveSyncManager {
  SelectiveSyncManager(
    this._db, {
    http.Client? client,
    this.joinRounds = kJoinKdfRounds,
    this.approvalTimeout = kJoinApprovalTimeout,
  }) : _client = client ?? http.Client();

  final OticDatabase _db;
  final http.Client _client;

  /// PBKDF2 rounds for join codes — lowered only in tests.
  final int joinRounds;

  /// How long a join waits for the sharer's Accept.
  final Duration approvalTimeout;

  static const _timeout = Duration(seconds: 20);

  // ── Join ────────────────────────────────────────────────────────────────

  /// Sends a join proof for [code] to each endpoint in turn and returns the
  /// first opened bundle. The code never leaves this device: only a proof
  /// derived from it does. Waits while the sharer decides.
  Future<Map<String, Object?>?> _requestJoin(
    List<TeacherEndpoint> endpoints,
    String code,
    String name,
  ) async {
    final salt = newNonce();
    final secret = await joinSecret(code, salt, rounds: joinRounds);
    final proof = await joinProof(secret, salt);
    for (final t in endpoints) {
      try {
        final response = await _client
            .post(
              Uri.parse('http://${t.address}:${t.port}/$kJoinPath'),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode({'nonce': salt, 'proof': proof, 'name': name}),
            )
            .timeout(approvalTimeout + _timeout);
        if (response.statusCode != 200) continue;
        final opened = await openJoinBundle(
          secret,
          salt,
          (jsonDecode(response.body) as Map)['bundle'],
        );
        if (opened is Map) return Map<String, Object?>.from(opened);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Tries [typedCode] against each teacher on the network, as [name].
  Future<JoinResult> joinClass({
    required List<TeacherEndpoint> teachers,
    required String typedCode,
    String name = '',
  }) async {
    final code = normalizeJoinCode(typedCode);
    if (code == null) {
      return const JoinResult.failed(
        'That isn’t a join code — it has 8 letters and numbers, like K7M4-P9QX.',
      );
    }
    if (teachers.isEmpty) {
      return const JoinResult.failed(
        'No teacher is sharing a class on this Wi-Fi right now.',
      );
    }
    final bundle = await _requestJoin(teachers, code, name);
    if (bundle == null) {
      return const JoinResult.failed(
        'You weren’t let in. Check the code, that it hasn’t expired, and that '
        'your teacher tapped Accept.',
      );
    }
    return _acceptBundle(bundle);
  }

  Future<JoinResult> _acceptBundle(Map<String, Object?> b) async {
    final schoolId = b['school_id'], schoolName = b['school_name'];
    final uuid = b['class_group_uuid'], className = b['class_name'];
    final classKey = b['class_key'], teacherKey = b['teacher_public_key'];
    final stream = b['stream_name'];
    if (schoolId is! String ||
        uuid is! String ||
        className is! String ||
        classKey is! String ||
        teacherKey is! String) {
      return const JoinResult.failed(
        'The teacher’s device sent incomplete class details.',
      );
    }
    final school = schoolName is String ? schoolName : '';

    final me = await _db.classSyncDao.identity();
    if (me.schoolId != null && me.schoolId != schoolId) {
      return JoinResult.failed(
        'This device belongs to ${me.schoolName ?? 'another school'}. '
        'That class is at ${school.isEmpty ? 'a different school' : school}, so it can’t be joined here.',
      );
    }
    final group = await _db.classSyncDao.upsertJoinedClass(
      groupUuid: uuid,
      className: className,
      streamName: stream is String && stream.isNotEmpty ? stream : null,
      schoolId: schoolId,
      classKey: classKey,
      teacherPublicKey: teacherKey,
    );
    if (group == null) {
      return const JoinResult.failed(
        'This device is the teacher’s own device for that class.',
      );
    }
    await _db.classSyncDao.adoptSchool(schoolId: schoolId, schoolName: school);
    return JoinResult.joined(group, school);
  }

  /// Tries a classmate's [typedCode]. Only works for a class this device
  /// already joined through the teacher — a classmate can pass the
  /// teacher's notes on, never let someone into the class.
  Future<ClassmateJoinResult> joinClassmate({
    required List<TeacherEndpoint> classmates,
    required String typedCode,
    String name = '',
  }) async {
    final code = normalizeJoinCode(typedCode);
    if (code == null) {
      return const ClassmateJoinResult.failed(
        'That isn’t a code — it has 8 letters and numbers, like K7M4-P9QX.',
      );
    }
    if (classmates.isEmpty) {
      return const ClassmateJoinResult.failed(
        'No classmate is sharing on this Wi-Fi right now. Type their '
        'address if they are.',
      );
    }
    final salt = newNonce();
    final secret = await joinSecret(code, salt, rounds: joinRounds);
    final proof = await joinProof(secret, salt);
    for (final c in classmates) {
      final Map<String, Object?> b;
      try {
        final response = await _client
            .post(
              Uri.parse('http://${c.address}:${c.port}/$kJoinPath'),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode({'nonce': salt, 'proof': proof, 'name': name}),
            )
            .timeout(approvalTimeout + _timeout);
        if (response.statusCode != 200) continue;
        final opened = await openJoinBundle(
          secret,
          salt,
          (jsonDecode(response.body) as Map)['bundle'],
        );
        if (opened is! Map) continue;
        b = Map<String, Object?>.from(opened);
      } catch (_) {
        continue;
      }
      final uuid = b['class_group_uuid'], token = b['session_token'];
      if (uuid is! String || token is! String) {
        return const ClassmateJoinResult.failed(
          'Your classmate’s device sent incomplete details.',
        );
      }
      final group = await _db.classSyncDao.joinedByUuid(uuid);
      if (group == null || group.schoolId != b['school_id']) {
        return const ClassmateJoinResult.failed(
          'That classmate is sharing a class this device hasn’t joined. Join '
          'your class with your teacher’s code first.',
        );
      }
      return ClassmateJoinResult.joined(
        ClassmateSession(endpoint: c, group: group, token: token),
      );
    }
    return const ClassmateJoinResult.failed(
      'You weren’t let in. Check the code, that it hasn’t expired, and that '
      'your classmate tapped Accept.',
    );
  }

  // ── Sync with the teacher ───────────────────────────────────────────────

  /// Pulls every subject [group] has shared notes in from [teacher].
  Future<SyncResult> syncClass({
    required TeacherEndpoint teacher,
    required ClassGroup group,
  }) async {
    final uuid = group.groupUuid, classKey = group.classKey;
    final teacherKey = group.teacherPublicKey, schoolId = group.schoolId;
    if (!group.joined ||
        uuid == null ||
        classKey == null ||
        teacherKey == null ||
        schoolId == null) {
      return SyncResult.failed('Join this class with your teacher’s code first.');
    }
    Future<Map<String, Object?>> call(
      String path,
      Map<String, Object?> body, {
      Future<Map<String, Object?>> Function(String nonce)? extra,
    }) => _signedCall(
      teacher,
      path,
      body,
      uuid: uuid,
      macKey: classKey,
      extra: extra,
      open: (nonce, sealed) => openReply(
        classKey: classKey,
        teacherPublicKey: teacherKey,
        requestNonce: nonce,
        sealed: sealed,
      ),
    );

    final List<ChannelManifest> manifests;
    try {
      manifests = await _manifests(
        await call(kHandshakePath, {'school_id': schoolId}),
        schoolId: schoolId,
        classUuid: uuid,
      );
    } catch (e) {
      return SyncResult.failed(
        e is SyncTrustError
            ? 'That device isn’t your class’s teacher: ${e.message}.'
            : 'Could not sync with the teacher’s device. Make sure it is still sharing '
                  '${group.className}${group.streamName == null ? '' : ' ${group.streamName}'}.',
      );
    }

    // Straight from the teacher, the list of subjects is authoritative:
    // anything not on it was unshared.
    final removed = await _db.classSyncDao.dropChannelsExcept(uuid, {
      for (final m in manifests) m.subjectId,
    });
    final run = await _pullChannels(
      manifests,
      group: group,
      call: (path, body) => call(path, body),
      fromTeacher: true,
    );

    // Then tell the teacher how this device's learners in the class are
    // doing. Best-effort: a failed report never fails the sync.
    var reported = 0;
    try {
      final me = await _db.classSyncDao.identity();
      final deviceKey = (await signingPublicKey(me.signingSeed)).substring(
        0,
        16,
      );
      final reports = await buildProgressReports(
        _db,
        group,
        deviceKey: deviceKey,
      );
      if (reports.isNotEmpty) {
        final ack = await call(
          kReportPath,
          {'school_id': schoolId},
          extra: (nonce) async => {
            'report': await sealReport(
              classKey: classKey,
              requestNonce: nonce,
              json: [for (final r in reports) r.toJson()],
            ),
          },
        );
        reported = ack['saved'] is int ? ack['saved'] as int : 0;
      }
    } catch (_) {}

    return SyncResult(
      subjectsChecked: manifests.length,
      subjectsUpdated: run.updated,
      chunksInserted: run.inserted,
      subjectsRemoved: removed,
      rejected: run.rejected,
      learnersReported: reported,
    );
  }

  // ── Sync with a classmate ───────────────────────────────────────────────

  /// Pulls from a classmate every subject whose teacher-signed version is
  /// newer than this device's. Never removes anything: a classmate's list
  /// says nothing about what the teacher still shares.
  Future<SyncResult> syncFromClassmate(ClassmateSession session) async {
    final group = session.group;
    final uuid = group.groupUuid!, classKey = group.classKey!;
    final schoolId = group.schoolId!;
    Future<Map<String, Object?>> call(String path, Map<String, Object?> body) =>
        _signedCall(
          session.endpoint,
          path,
          body,
          uuid: uuid,
          macKey: session.token,
          open: (nonce, sealed) => openRelayReply(
            classKey: classKey,
            requestNonce: nonce,
            sealed: sealed,
          ),
        );

    final List<ChannelManifest> manifests;
    try {
      manifests = await _manifests(
        await call(kHandshakePath, {'school_id': schoolId}),
        schoolId: schoolId,
        classUuid: uuid,
      );
    } catch (e) {
      return SyncResult.failed(
        'Could not get notes from your classmate. Make sure they are still '
        'sharing, then try again.',
      );
    }
    final run = await _pullChannels(
      manifests,
      group: group,
      call: call,
      fromTeacher: false,
    );
    return SyncResult(
      subjectsChecked: manifests.length,
      subjectsUpdated: run.updated,
      chunksInserted: run.inserted,
      rejected: run.rejected,
    );
  }

  // ── Shared pulling ──────────────────────────────────────────────────────

  Future<List<ChannelManifest>> _manifests(
    Map<String, Object?> hello, {
    required String schoolId,
    required String classUuid,
  }) async {
    final out = <ChannelManifest>[];
    for (final s in (hello['subjects'] as List? ?? const [])) {
      final m = ChannelManifest.fromJson(
        s,
        schoolId: schoolId,
        classUuid: classUuid,
      );
      if (m != null) out.add(m);
    }
    return out;
  }

  Future<({int updated, int inserted, List<RejectedChunk> rejected})>
  _pullChannels(
    List<ChannelManifest> manifests, {
    required ClassGroup group,
    required Future<Map<String, Object?>> Function(
      String path,
      Map<String, Object?> body,
    )
    call,
    required bool fromTeacher,
  }) async {
    final uuid = group.groupUuid!;
    final dao = _db.classSyncDao;
    var updated = 0;
    var inserted = 0;
    final rejected = <RejectedChunk>[];

    for (final m in manifests) {
      final routingKey = '$uuid/${m.subjectId}';
      try {
        if (!await verifyManifest(m, group.teacherPublicKey!)) {
          rejected.add(
            RejectedChunk(
              reason: 'not signed by your class’s teacher',
              routingKey: routingKey,
            ),
          );
          continue;
        }
        final local = await dao.channelState(uuid, m.subjectId);
        if (fromTeacher) {
          if (local?.channelDigest == m.digest) {
            if (local!.channelVersion != m.version ||
                local.manifestSig != m.signature) {
              await dao.updateManifest(
                classUuid: uuid,
                subjectId: m.subjectId,
                version: m.version,
                manifestSig: m.signature,
              );
            }
            continue;
          }
        } else {
          // From a classmate: only strictly newer than what this device
          // has — including a subject the teacher removed (tombstone).
          final have = local?.channelVersion;
          if (have != null && m.version <= have) continue;
          if (local?.channelDigest == m.digest && have == null) {
            await dao.updateManifest(
              classUuid: uuid,
              subjectId: m.subjectId,
              version: m.version,
              manifestSig: m.signature,
            );
            continue;
          }
        }

        final reply = await call(kChannelPath, {
          'school_id': group.schoolId,
          'subject_id': m.subjectId,
        });
        final rows = <TopicResourcesCompanion>[];
        final ids = <String>[];
        final bad = <RejectedChunk>[];
        for (final raw in (reply['chunks'] as List? ?? const [])) {
          try {
            final envelope = ResourceChunkEnvelope.fromJson(raw);
            rows.add(_ingest(envelope, routingKey, uuid, m.subjectId));
            ids.add(envelope.chunkId);
          } on FormatException catch (e) {
            bad.add(RejectedChunk(reason: e.message, routingKey: routingKey));
          } on StateError catch (e) {
            bad.add(RejectedChunk(reason: e.message, routingKey: routingKey));
          }
        }
        final digest = await channelDigest(ids);
        if (bad.isEmpty && digest != m.digest) {
          bad.add(
            RejectedChunk(
              reason: fromTeacher
                  ? 'the notes changed while syncing — sync again'
                  : 'the notes don’t match what your teacher signed',
              routingKey: routingKey,
            ),
          );
        }
        if (bad.isNotEmpty) {
          // All or nothing: keep the copy this device already has.
          rejected.addAll(bad);
          continue;
        }
        await dao.replaceChannel(
          classUuid: uuid,
          subjectId: m.subjectId,
          rows: rows,
          digest: digest,
          version: m.version,
          manifestSig: m.signature,
        );
        updated++;
        inserted += rows.length;
      } catch (e) {
        rejected.add(
          RejectedChunk(
            reason: e is SyncTrustError ? e.message : 'subject failed: $e',
            routingKey: routingKey,
          ),
        );
      }
    }
    return (updated: updated, inserted: inserted, rejected: rejected);
  }

  Future<Map<String, Object?>> _signedCall(
    TeacherEndpoint endpoint,
    String path,
    Map<String, Object?> body, {
    required String uuid,
    required String macKey,
    required Future<Object?> Function(String nonce, Object? sealed) open,
    Future<Map<String, Object?>> Function(String nonce)? extra,
  }) async {
    final nonce = newNonce();
    final raw = jsonEncode({...body, if (extra != null) ...await extra(nonce)});
    final response = await _client
        .post(
          Uri.parse('http://${endpoint.address}:${endpoint.port}/$path'),
          headers: {
            'content-type': 'application/json',
            kClassHeader: uuid,
            kNonceHeader: nonce,
            kMacHeader: await requestMac(
              classKey: macKey,
              path: path,
              nonce: nonce,
              body: raw,
            ),
          },
          body: raw,
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError(
        'the sharing device refused this request (${response.statusCode})',
      );
    }
    final opened = await open(nonce, jsonDecode(response.body));
    if (opened is! Map) throw const SyncTrustError('reply is not an object');
    return Map<String, Object?>.from(opened);
  }

  /// One chunk's checks: its routing key names this class+subject, and its
  /// content matches its own hash.
  TopicResourcesCompanion _ingest(
    ResourceChunkEnvelope envelope,
    String expectedRoutingKey,
    String classUuid,
    String subjectId,
  ) {
    if (envelope.routingKey != expectedRoutingKey) {
      throw StateError(
        'routing key mismatch: expected $expectedRoutingKey, got ${envelope.routingKey}',
      );
    }
    if (!envelope.hashMatches) {
      throw StateError('chunk content does not match its id');
    }
    final p = envelope.payload;
    final topicKey = p['topic_key'], termMarker = p['term_marker'];
    final title = p['resource_title'], content = p['content_chunk'];
    final createdAt = p['created_at'], updatedAt = p['updated_at'];
    if (p['subject_id'] != subjectId ||
        topicKey is! String ||
        termMarker is! int ||
        title is! String ||
        content is! String ||
        createdAt is! String) {
      throw const FormatException('payload missing or mistyped fields');
    }
    return TopicResourcesCompanion.insert(
      subjectId: subjectId,
      topicKey: topicKey,
      termMarker: Value(termMarker),
      resourceTitle: title,
      contentChunk: content,
      createdAt: createdAt,
      classGroupUuid: Value(classUuid),
      updatedAt: Value(updatedAt is String ? updatedAt : createdAt),
      documentTitle: Value(
        p['document_title'] is String ? p['document_title'] as String : title,
      ),
    );
  }

  void dispose() => _client.close();
}
