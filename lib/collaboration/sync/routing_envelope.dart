import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../../db/tables/topic_resources_table.dart' show kAllTermsMarker;

/// Informational label for [ResourceChunkEnvelope.term] — display/logging
/// only. The value that actually round-trips a row is [payload]'s
/// `term_marker` int; this map exists so the envelope reads like the wire
/// format everyone agreed on, without depending on `ResourceLabels`, which
/// needs a `BuildContext` this layer never has.
const Map<int, String> kTermMarkerLabels = {
  kAllTermsMarker: 'All terms',
  1: 'Term 1',
  2: 'Term 2',
  3: 'Term 3',
};

String termLabelForSync(int marker) =>
    kTermMarkerLabels[marker] ?? 'Term $marker';

/// SHA-256 over the canonical JSON encoding of [payload] — the envelope's
/// `chunk_id`. Canonical means one fixed key order (sorted), so the same
/// logical chunk always hashes the same way regardless of how the Map that
/// produced it was built; without that, `{"a":1,"b":2}` and `{"b":2,"a":1}`
/// would hash differently for content that is actually identical.
String chunkHash(Map<String, Object?> payload) {
  final sortedKeys = payload.keys.toList()..sort();
  final canonical = <String, Object?>{
    for (final k in sortedKeys) k: payload[k],
  };
  final bytes = utf8.encode(jsonEncode(canonical));
  return sha256.convert(bytes).toString();
}

/// One routed resource chunk, as it travels between a teacher's sync server
/// and a student's [SelectiveSyncManager].
///
/// [routingKey] is always `<classGroupUuid>/<subjectId>` for the channel the
/// request was actually served on — not necessarily where the underlying
/// `topic_resources` row is scoped, since a class-agnostic row (`null`
/// `classGroupUuid`) is served on every class's channel. A receiver that
/// only ever asked for one channel does not need to re-derive that; it is
/// carried so a malformed or mismatched key can be caught and the block
/// rejected without guessing what the sender meant (see
/// [SelectiveSyncManager._ingestEnvelope]).
class ResourceChunkEnvelope {
  const ResourceChunkEnvelope({
    required this.routingKey,
    required this.term,
    required this.chunkId,
    required this.payload,
  });

  final String routingKey;
  final String term;
  final String chunkId;
  final Map<String, Object?> payload;

  /// Builds an envelope from a `topic_resources` row already known to belong
  /// to [classGroupUuid]'s channel (see `TopicResourceDao.channelChunks`).
  factory ResourceChunkEnvelope.forChannel({
    required String classGroupUuid,
    required String subjectId,
    required String topicKey,
    required int termMarker,
    required String resourceTitle,
    required String contentChunk,
    required String createdAt,
    String? updatedAt,
  }) {
    final payload = <String, Object?>{
      'subject_id': subjectId,
      'topic_key': topicKey,
      'term_marker': termMarker,
      'resource_title': resourceTitle,
      'content_chunk': contentChunk,
      'created_at': createdAt,
      'updated_at': updatedAt ?? createdAt,
    };
    return ResourceChunkEnvelope(
      routingKey: '$classGroupUuid/$subjectId',
      term: termLabelForSync(termMarker),
      chunkId: chunkHash(payload),
      payload: payload,
    );
  }

  Map<String, Object?> toJson() => {
        'routing_key': routingKey,
        'term': term,
        'chunk_id': chunkId,
        'payload': payload,
      };

  /// Parses one array entry from a `/sync/channel` response.
  ///
  /// Throws [FormatException] on anything malformed — callers must catch
  /// per-envelope (see [SelectiveSyncManager]), never let one bad entry
  /// abort the whole batch.
  static ResourceChunkEnvelope fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('envelope is not an object');
    }
    final routingKey = json['routing_key'];
    final term = json['term'];
    final chunkId = json['chunk_id'];
    final payload = json['payload'];
    if (routingKey is! String || routingKey.isEmpty) {
      throw const FormatException('missing or empty routing_key');
    }
    if (chunkId is! String || chunkId.isEmpty) {
      throw const FormatException('missing or empty chunk_id');
    }
    if (payload is! Map) {
      throw const FormatException('missing payload');
    }
    return ResourceChunkEnvelope(
      routingKey: routingKey,
      term: term is String ? term : '',
      chunkId: chunkId,
      payload: Map<String, Object?>.from(payload),
    );
  }

  /// True when [chunkId] actually matches [payload] — the integrity check
  /// every incoming envelope must pass before it is written anywhere.
  bool get hashMatches => chunkHash(payload) == chunkId;
}
