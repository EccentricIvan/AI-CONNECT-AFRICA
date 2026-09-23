import 'package:uuid/uuid.dart';

/// One shared generator for every portable id this feature mints — a class's
/// [groupUuid][1], and nothing else: subjects already have a stable slug
/// (`subjectId`), and a resource chunk's id is a content hash, not a random
/// one (see [chunkHash] in `routing_envelope.dart`).
///
/// [1]: lib/db/tables/class_groups_table.dart
const _uuid = Uuid();

String newSyncId() => _uuid.v4();
