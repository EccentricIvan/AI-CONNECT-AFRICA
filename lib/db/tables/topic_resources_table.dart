import 'package:drift/drift.dart';

/// Teacher-supplied notes, textbook extracts and term handouts, chunked for
/// offline retrieval.
///
/// This table is **additive**. The hardcoded syllabi in `assets/curriculum/*.json`
/// (loaded by `CurriculumService`) remain the permanent structural base for
/// every subject: nothing here replaces a lesson, and a subject with zero rows
/// in this table behaves exactly as it did before the table existed. Retrieval
/// returns an empty string in that case and the tutor falls back to the core
/// syllabus plus its own general knowledge.
///
/// Column names are the contract — drift lowers each camelCase getter to
/// snake_case, so this class produces precisely:
///
///   topic_resources(id, subject_id, topic_key, term_marker,
///                   resource_title, content_chunk, created_at)
@TableIndex(name: 'idx_topic_resources_lookup', columns: {#subjectId, #topicKey})
@TableIndex(name: 'idx_topic_resources_title', columns: {#resourceTitle})
class TopicResources extends Table {
  @override
  String get tableName => 'topic_resources';

  IntColumn get id => integer().autoIncrement()();

  /// Curriculum subject this resource belongs to, e.g. `chemistry`.
  ///
  /// Must be spelled the same way on write and on read or retrieval silently
  /// returns nothing forever — see `normalizeSubjectId`, which both sides call.
  TextColumn get subjectId => text()();

  /// Normalized lesson/topic identifier tying the resource to one point in the
  /// hardcoded syllabus. Always written through `normalizeTopicKey` so a
  /// teacher typing "Acid–Base Balances" and a chat turn on the lesson titled
  /// "Acid-Base Balances" land on the same key.
  TextColumn get topicKey => text()();

  /// School term this resource applies to: 1, 2 or 3.
  ///
  /// [kAllTermsMarker] (0) means "applies to every term", which is the right
  /// default for a textbook extract that is not term-specific.
  IntColumn get termMarker =>
      integer().withDefault(const Constant(kAllTermsMarker))();

  /// Human-readable name, e.g. "Acid-Base Balances Notes". Every chunk of one
  /// document shares the title — that is what makes deletion by title able to
  /// remove a whole resource in a single statement.
  TextColumn get resourceTitle => text()();

  /// One ~500-character slice of the resource's text. Stored as many small
  /// rows rather than one large blob so a retrieval can return the paragraphs
  /// that matter instead of a whole chapter — on a 4 GB device the prompt
  /// budget, not the disk, is the scarce resource.
  TextColumn get contentChunk => text()();

  /// ISO-8601 UTC timestamp. TEXT rather than drift's default integer
  /// `DateTimeColumn` so the physical column type matches the agreed schema.
  TextColumn get createdAt => text()();

  /// Scoped sync: which class/stream this chunk was pushed to, by
  /// [ClassGroups.groupUuid] — not [ClassGroups.id], which is device-local
  /// and meaningless once a chunk has travelled to a different device. Null
  /// means "every class" (the resource's state before this column existed,
  /// and the right default for a resource with no class-specific content),
  /// matching how `termMarker: 0` already means "every term".
  TextColumn get classGroupUuid => text().nullable()();

  /// ISO-8601 UTC. The version token a scoped-sync pull compares against a
  /// student device's `SyncState.lastSyncedAt` — null falls back to
  /// [createdAt], so a resource written before this column existed is still
  /// syncable (just always looks "current" until it is next edited).
  TextColumn get updatedAt => text().nullable()();
}

/// `term_marker` value meaning "every term".
const kAllTermsMarker = 0;

/// Valid `term_marker` values: all-terms, plus the three school terms.
const kTermMarkers = [kAllTermsMarker, 1, 2, 3];

/// Target size of one [TopicResources.contentChunk], in characters.
///
/// ~500 characters is roughly 120-150 tokens, so the three chunks a retrieval
/// returns stay well inside the prompt budget left over after the tutor
/// contract and the student's question.
const kResourceChunkSize = 500;
