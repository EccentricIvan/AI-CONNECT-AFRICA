import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../../db/otic_database.dart';
import 'class_crypto.dart';
import 'routing_envelope.dart';
import 'teacher_sync_server.dart'
    show
        kChannelPath,
        kClassHeader,
        kHandshakePath,
        kJoinPath,
        kMacHeader,
        kNonceHeader;

/// One malformed or mismatched block, kept for a post-sync report rather
/// than only a running count.
class RejectedChunk {
  const RejectedChunk({required this.reason, this.routingKey});
  final String reason;
  final String? routingKey;
}

/// What one [SelectiveSyncManager.syncClass] run actually did.
class SyncResult {
  const SyncResult({
    required this.subjectsChecked,
    required this.subjectsUpdated,
    required this.chunksInserted,
    required this.rejected,
    this.subjectsRemoved = 0,
    this.error,
  });

  final int subjectsChecked;
  final int subjectsUpdated;
  final int chunksInserted;
  final int subjectsRemoved;
  final List<RejectedChunk> rejected;

  /// Set only when the whole run failed before touching any subject.
  final String? error;

  bool get ok => error == null;
}

/// A teacher sync server seen on the network.
typedef TeacherEndpoint = ({String address, int port});

/// Outcome of typing a join code.
class JoinResult {
  const JoinResult.joined(ClassGroup this.group, this.schoolName)
    : error = null;
  const JoinResult.failed(String this.error) : group = null, schoolName = null;

  final ClassGroup? group;
  final String? schoolName;
  final String? error;
  bool get ok => group != null;
}

/// A student device's side of class sync: joining a class with the
/// teacher's code, then pulling that class's shared notes.
///
/// Each subject is replaced as a whole, in one transaction, and only when
/// every chunk checks out — a teacher's edits and removals arrive exactly,
/// and a bad reply never leaves half a subject behind. A failing subject
/// never stops the next one.
class SelectiveSyncManager {
  SelectiveSyncManager(
    this._db, {
    http.Client? client,
    this.joinRounds = kJoinKdfRounds,
  }) : _client = client ?? http.Client();

  final OticDatabase _db;
  final http.Client _client;

  /// PBKDF2 rounds for join codes — lowered only in tests.
  final int joinRounds;

  static const _timeout = Duration(seconds: 20);

  // ── Join ────────────────────────────────────────────────────────────────

  /// Tries [typedCode] against each teacher on the network. The code never
  /// leaves this device: only a proof derived from it does.
  Future<JoinResult> joinClass({
    required List<TeacherEndpoint> teachers,
    required String typedCode,
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
    final salt = newNonce();
    final secret = await joinSecret(code, salt, rounds: joinRounds);
    final proof = await joinProof(secret, salt);

    for (final t in teachers) {
      final Map<String, Object?> bundle;
      try {
        final response = await _client
            .post(
              Uri.parse('http://${t.address}:${t.port}/$kJoinPath'),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode({'nonce': salt, 'proof': proof}),
            )
            .timeout(_timeout);
        if (response.statusCode != 200) continue;
        final opened = await openJoinBundle(
          secret,
          salt,
          (jsonDecode(response.body) as Map)['bundle'],
        );
        if (opened is! Map) continue;
        bundle = Map<String, Object?>.from(opened);
      } catch (_) {
        continue;
      }
      return _acceptBundle(bundle);
    }
    return const JoinResult.failed(
      'No teacher accepted that code. Check it, and that the code hasn’t expired.',
    );
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

  // ── Sync ────────────────────────────────────────────────────────────────

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
      return const SyncResult(
        subjectsChecked: 0,
        subjectsUpdated: 0,
        chunksInserted: 0,
        rejected: [],
        error: 'Join this class with your teacher’s code first.',
      );
    }
    Future<Map<String, Object?>> call(String path, Map<String, Object?> body) =>
        _signedCall(
          teacher,
          path,
          body,
          uuid: uuid,
          classKey: classKey,
          teacherKey: teacherKey,
        );

    final Map<String, int> subjectsSeen;
    final Map<String, String> digests;
    try {
      final hello = await call(kHandshakePath, {'school_id': schoolId});
      digests = {};
      for (final s in (hello['subjects'] as List? ?? const [])) {
        if (s is Map && s['subject_id'] is String && s['digest'] is String) {
          digests[s['subject_id'] as String] = s['digest'] as String;
        }
      }
      subjectsSeen = {for (final s in digests.keys) s: 0};
    } catch (e) {
      return SyncResult(
        subjectsChecked: 0,
        subjectsUpdated: 0,
        chunksInserted: 0,
        rejected: const [],
        error: e is SyncTrustError
            ? 'That device isn’t your class’s teacher: ${e.message}.'
            : 'Could not sync with the teacher’s device. Make sure it is still sharing '
                  '${group.className}${group.streamName == null ? '' : ' ${group.streamName}'}.',
      );
    }

    final removed = await _db.classSyncDao.dropChannelsExcept(
      uuid,
      subjectsSeen.keys.toSet(),
    );
    var updated = 0;
    var inserted = 0;
    final rejected = <RejectedChunk>[];

    for (final entry in digests.entries) {
      final subject = entry.key;
      final routingKey = '$uuid/$subject';
      try {
        if (await _db.classSyncDao.channelDigestFor(uuid, subject) ==
            entry.value) {
          continue;
        }

        final reply = await call(kChannelPath, {
          'school_id': schoolId,
          'subject_id': subject,
        });
        final rows = <TopicResourcesCompanion>[];
        final ids = <String>[];
        final bad = <RejectedChunk>[];
        for (final raw in (reply['chunks'] as List? ?? const [])) {
          try {
            final envelope = ResourceChunkEnvelope.fromJson(raw);
            rows.add(_ingest(envelope, routingKey, uuid, subject));
            ids.add(envelope.chunkId);
          } on FormatException catch (e) {
            bad.add(RejectedChunk(reason: e.message, routingKey: routingKey));
          } on StateError catch (e) {
            bad.add(RejectedChunk(reason: e.message, routingKey: routingKey));
          }
        }
        final digest = await channelDigest(ids);
        if (bad.isEmpty &&
            (digest != reply['digest'] || digest != entry.value)) {
          bad.add(
            RejectedChunk(
              reason: 'the notes changed while syncing — sync again',
              routingKey: routingKey,
            ),
          );
        }
        if (bad.isNotEmpty) {
          // All or nothing: keep the copy this device already has.
          rejected.addAll(bad);
          continue;
        }
        await _db.classSyncDao.replaceChannel(
          classUuid: uuid,
          subjectId: subject,
          rows: rows,
          digest: digest,
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

    return SyncResult(
      subjectsChecked: digests.length,
      subjectsUpdated: updated,
      chunksInserted: inserted,
      subjectsRemoved: removed,
      rejected: rejected,
    );
  }

  Future<Map<String, Object?>> _signedCall(
    TeacherEndpoint teacher,
    String path,
    Map<String, Object?> body, {
    required String uuid,
    required String classKey,
    required String teacherKey,
  }) async {
    final raw = jsonEncode(body);
    final nonce = newNonce();
    final response = await _client
        .post(
          Uri.parse('http://${teacher.address}:${teacher.port}/$path'),
          headers: {
            'content-type': 'application/json',
            kClassHeader: uuid,
            kNonceHeader: nonce,
            kMacHeader: await requestMac(
              classKey: classKey,
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
        'the teacher’s device refused this request (${response.statusCode})',
      );
    }
    final opened = await openReply(
      classKey: classKey,
      teacherPublicKey: teacherKey,
      requestNonce: nonce,
      sealed: jsonDecode(response.body),
    );
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
