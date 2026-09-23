import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../../db/otic_database.dart';
import 'routing_envelope.dart';

/// One malformed or mismatched block, kept for a post-sync report rather
/// than only a running count — a teacher/parent looking at "3 rejected"
/// with no detail cannot tell a hash mismatch (possible corruption) from a
/// stale server (harmless, self-resolving).
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
    this.error,
  });

  final int subjectsChecked;
  final int subjectsUpdated;
  final int chunksInserted;
  final List<RejectedChunk> rejected;

  /// Set only when the whole run failed before touching any subject (e.g.
  /// the teacher server was unreachable, or the class id it reported is
  /// unknown to it) — a single subject's failure never reaches here, since
  /// [syncClass] isolates subjects from each other (see its loop).
  final String? error;

  bool get ok => error == null;
}

/// Pulls scoped class/stream/subject material from a [TeacherSyncServer] on
/// the same local network into this device's own `topic_resources`.
///
/// Isolation is the design, not an afterthought: a channel that fails (bad
/// JSON, unreachable, wrong routing key) never stops the next channel; a
/// chunk that fails its hash check never stops the next chunk. A sync that
/// discovers a nasty file (or a nasty peer) should end with an honest
/// [SyncResult] the caller can show, not a stack trace and half-written data.
class SelectiveSyncManager {
  SelectiveSyncManager(this._db, {http.Client? client})
      : _client = client ?? http.Client();

  final OticDatabase _db;
  final http.Client _client;

  /// Chunks written to `topic_resources` per `batch()` transaction — small
  /// and yielded between, so a large first sync does not hold the UI isolate
  /// for one long uninterrupted write on a 4 GB device.
  static const _writeBatchSize = 50;

  static const _timeout = Duration(seconds: 20);

  /// Syncs every subject [classGroupUuid] has material for, from the teacher
  /// server at `http://$teacherAddress:$teacherPort`.
  Future<SyncResult> syncClass({
    required String teacherAddress,
    required int teacherPort,
    required String classGroupUuid,
  }) async {
    final base = 'http://$teacherAddress:$teacherPort';

    final List<SubjectHandshake> subjects;
    try {
      subjects = await _handshake(base, classGroupUuid);
    } catch (e) {
      return SyncResult(
        subjectsChecked: 0,
        subjectsUpdated: 0,
        chunksInserted: 0,
        rejected: const [],
        error: 'Could not reach the teacher device: $e',
      );
    }

    var updated = 0;
    var inserted = 0;
    final rejected = <RejectedChunk>[];

    for (final subject in subjects) {
      try {
        final local = await _db.syncStateDao.get(
          classGroupUuid: classGroupUuid,
          subjectId: subject.subjectId,
        );
        final since = local?.lastSyncedAt;
        // Plain string compare is correct here — every version this app
        // writes is ISO-8601 UTC with the same fixed-width format, which
        // sorts identically to a real date comparison.
        if (since != null && since.compareTo(subject.version) >= 0) {
          continue; // Already at (or somehow past) this version.
        }

        final channelResult = await _pullChannel(
          base: base,
          classGroupUuid: classGroupUuid,
          subjectId: subject.subjectId,
          since: since,
        );
        rejected.addAll(channelResult.rejected);
        if (channelResult.rows.isNotEmpty) {
          await _writeBatched(channelResult.rows);
          inserted += channelResult.rows.length;
        }

        await _db.syncStateDao.recordSync(
          classGroupUuid: classGroupUuid,
          subjectId: subject.subjectId,
          syncedAtIso: subject.version,
          rejectedThisRun: channelResult.rejected.length,
        );
        if (channelResult.rows.isNotEmpty) updated++;
      } catch (e) {
        // One subject's channel failing (bad JSON, dropped connection mid
        // pull) must not stop the rest — a phone that walks out of hotspot
        // range partway through should keep whatever it already got.
        rejected.add(RejectedChunk(
          reason: 'channel failed: $e',
          routingKey: '$classGroupUuid/${subject.subjectId}',
        ));
      }
    }

    return SyncResult(
      subjectsChecked: subjects.length,
      subjectsUpdated: updated,
      chunksInserted: inserted,
      rejected: rejected,
    );
  }

  Future<List<SubjectHandshake>> _handshake(
    String base,
    String classGroupUuid,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$base/api/v1/sync/handshake'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'class_group_uuid': classGroupUuid}),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('handshake failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['subjects'] is! List) {
      throw const FormatException('malformed handshake response');
    }
    final subjects = <SubjectHandshake>[];
    for (final raw in decoded['subjects'] as List) {
      if (raw is! Map) continue;
      final id = raw['subject_id'];
      final version = raw['version'];
      if (id is String && id.isNotEmpty && version is String) {
        subjects.add(SubjectHandshake(subjectId: id, version: version));
      }
    }
    return subjects;
  }

  Future<_ChannelPull> _pullChannel({
    required String base,
    required String classGroupUuid,
    required String subjectId,
    String? since,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$base/api/v1/sync/channel'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'class_group_uuid': classGroupUuid,
            'subject_id': subjectId,
            if (since != null) 'since': since,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('channel pull failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['chunks'] is! List) {
      throw const FormatException('malformed channel response');
    }

    final expectedRoutingKey = '$classGroupUuid/$subjectId';
    final rows = <TopicResourcesCompanion>[];
    final rejected = <RejectedChunk>[];

    for (final raw in decoded['chunks'] as List) {
      try {
        final row = _ingestEnvelope(raw, expectedRoutingKey, classGroupUuid);
        rows.add(row);
      } on FormatException catch (e) {
        rejected.add(RejectedChunk(reason: e.message));
      } on StateError catch (e) {
        rejected.add(
          RejectedChunk(reason: e.message, routingKey: expectedRoutingKey),
        );
      }
    }
    return _ChannelPull(rows: rows, rejected: rejected);
  }

  /// One block's fail-safe boundary: a malformed envelope, a routing key
  /// that does not match the channel it arrived on, or a payload whose hash
  /// does not match its own `chunk_id` are all rejected individually —
  /// never thrown past this method to abort the rest of the channel.
  TopicResourcesCompanion _ingestEnvelope(
    Object? raw,
    String expectedRoutingKey,
    String classGroupUuid,
  ) {
    final envelope = ResourceChunkEnvelope.fromJson(raw);

    if (envelope.routingKey != expectedRoutingKey) {
      throw StateError(
        'routing key mismatch: expected $expectedRoutingKey, '
        'got ${envelope.routingKey}',
      );
    }
    if (!envelope.hashMatches) {
      throw StateError('chunk_id does not match payload — possible '
          'corruption or tampering');
    }

    final payload = envelope.payload;
    final subjectId = payload['subject_id'];
    final topicKey = payload['topic_key'];
    final termMarker = payload['term_marker'];
    final resourceTitle = payload['resource_title'];
    final contentChunk = payload['content_chunk'];
    final createdAt = payload['created_at'];
    final updatedAt = payload['updated_at'];

    if (subjectId is! String ||
        topicKey is! String ||
        termMarker is! int ||
        resourceTitle is! String ||
        contentChunk is! String ||
        createdAt is! String) {
      throw const FormatException('payload missing or mistyped fields');
    }

    return TopicResourcesCompanion.insert(
      subjectId: subjectId,
      topicKey: topicKey,
      termMarker: Value(termMarker),
      resourceTitle: resourceTitle,
      contentChunk: contentChunk,
      createdAt: createdAt,
      classGroupUuid: Value(classGroupUuid),
      updatedAt: Value(updatedAt is String ? updatedAt : createdAt),
    );
  }

  Future<void> _writeBatched(List<TopicResourcesCompanion> rows) async {
    for (var i = 0; i < rows.length; i += _writeBatchSize) {
      final slice = rows.sublist(
        i,
        i + _writeBatchSize > rows.length ? rows.length : i + _writeBatchSize,
      );
      await _db.topicResourceDao.insertChunks(slice);
      // Yield between batches so a big first sync stays responsive rather
      // than running every insert back-to-back inside one microtask chain.
      await Future<void>.delayed(Duration.zero);
    }
  }

  void dispose() => _client.close();
}

class SubjectHandshake {
  const SubjectHandshake({required this.subjectId, required this.version});
  final String subjectId;
  final String version;
}

class _ChannelPull {
  const _ChannelPull({required this.rows, required this.rejected});
  final List<TopicResourcesCompanion> rows;
  final List<RejectedChunk> rejected;
}
