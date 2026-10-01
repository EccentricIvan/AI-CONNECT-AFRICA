import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../db/daos/topic_resource_dao.dart' show kPdfMarkerTopicKey;
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';

/// Topic key of the one row per note that records its original PDF.
const kPdfMarkerTopic = kPdfMarkerTopicKey;

/// Largest PDF kept and synced. Bigger files still become notes; only the
/// original isn't kept.
const kMaxNotePdfBytes = 40 * 1024 * 1024;

/// The original PDF behind a note, as recorded in its marker row.
///
/// The marker is an ordinary `topic_resources` row of the note, so it rides
/// on everything the note already does: the teacher's signed channel digest
/// covers it (a classmate can't swap the file), it is shared and unshared
/// with the note, deleted with it, and carried in a failover ledger. Only
/// the bytes travel separately, and they are checked against [sha256].
class NotePdf {
  const NotePdf({
    required this.sha256,
    required this.pages,
    required this.bytes,
    required this.subjectId,
    required this.documentTitle,
    this.classGroupUuid,
  });

  final String sha256;
  final int pages;
  final int bytes;
  final String subjectId;
  final String documentTitle;

  /// Null for this device's own note; the class it came from otherwise.
  final String? classGroupUuid;

  static final _pattern = RegExp(
    r'^\[PDF: sha256=([0-9a-f]{64}) \| pages=(\d+) \| bytes=(\d+)\]$',
  );

  static String markerText(String sha256, int pages, int bytes) =>
      '[PDF: sha256=$sha256 | pages=$pages | bytes=$bytes]';

  /// The PDF a marker row records, or null if [row] isn't one.
  static NotePdf? fromRow(TopicResource row) {
    if (row.topicKey != kPdfMarkerTopic) return null;
    final m = _pattern.firstMatch(row.contentChunk.trim());
    if (m == null) return null;
    return NotePdf(
      sha256: m[1]!,
      pages: int.parse(m[2]!),
      bytes: int.parse(m[3]!),
      subjectId: row.subjectId,
      documentTitle: row.documentTitle ?? row.resourceTitle,
      classGroupUuid: row.classGroupUuid,
    );
  }
}

/// Original PDFs of teacher notes, stored once each under their SHA-256 in
/// the app's private storage.
class NotePdfStore {
  NotePdfStore(
    this._db, {
    Future<Directory> Function()? root,
    this.gcGrace = const Duration(minutes: 10),
  }) : _root = root ?? _defaultRoot;

  /// [collectGarbage] leaves files younger than this: an import or sync may
  /// have written one and not recorded it yet.
  final Duration gcGrace;

  final OticDatabase _db;
  final Future<Directory> Function() _root;

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}otic_note_pdfs');
  }

  Future<Directory> _dir() async {
    final d = await _root();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String sha) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$sha.pdf');

  static String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

  /// The stored file for [sha], or null when this device doesn't have it.
  Future<File?> fileFor(String sha) async {
    final f = await _file(sha);
    return await f.exists() ? f : null;
  }

  Future<bool> has(String sha) async => (await fileFor(sha)) != null;

  /// Stores [bytes] if they hash to [expectedSha] (or, with none, to
  /// whatever they hash to). Returns the hash, or null when they don't
  /// match or are too big.
  Future<String?> put(Uint8List bytes, {String? expectedSha}) async {
    if (bytes.isEmpty || bytes.length > kMaxNotePdfBytes) return null;
    final sha = await compute(hashOf, bytes);
    if (expectedSha != null && sha != expectedSha) return null;
    final f = await _file(sha);
    if (await f.exists() && await f.length() == bytes.length) return sha;
    // Write beside, then rename: a half-written file is never taken for
    // the real one.
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    return sha;
  }

  /// Records [sha] as the original of this device's note [documentTitle] in
  /// [subjectId], replacing any earlier record.
  Future<void> recordOwn({
    required String subjectId,
    required String documentTitle,
    required String sha,
    required int pages,
    required int bytes,
    int termMarker = 0,
  }) => _db.transaction(() async {
    await (_db.delete(_db.topicResources)..where(
          (t) =>
              t.subjectId.equals(subjectId) &
              t.documentTitle.equals(documentTitle) &
              t.topicKey.equals(kPdfMarkerTopic) &
              t.classGroupUuid.isNull(),
        ))
        .go();
    await _db
        .into(_db.topicResources)
        .insert(
          TopicResourcesCompanion.insert(
            subjectId: subjectId,
            topicKey: kPdfMarkerTopic,
            termMarker: Value(termMarker),
            resourceTitle: documentTitle,
            contentChunk: NotePdf.markerText(sha, pages, bytes),
            createdAt: DateTime.now().toUtc().toIso8601String(),
            documentTitle: Value(documentTitle),
          ),
        );
  });

  /// Every PDF recorded on this device: its own notes' and, with
  /// [classUuid], those received for that class.
  Future<List<NotePdf>> recorded({
    String? subjectId,
    String? classUuid,
    bool ownOnly = false,
  }) async {
    final q = _db.select(_db.topicResources)
      ..where((t) => t.topicKey.equals(kPdfMarkerTopic));
    if (subjectId != null) q.where((t) => t.subjectId.equals(subjectId));
    if (ownOnly) {
      q.where((t) => t.classGroupUuid.isNull());
    } else if (classUuid != null) {
      q.where((t) => t.classGroupUuid.equals(classUuid));
    }
    return [
      for (final r in await q.get())
        if (NotePdf.fromRow(r) case final pdf?) pdf,
    ];
  }

  /// This device's own note PDFs, plus [classUuid]'s received ones —
  /// what a learner in that class may open.
  Future<List<NotePdf>> visibleTo(String? classUuid) async => [
    ...await recorded(ownOnly: true),
    if (classUuid != null) ...await recorded(classUuid: classUuid),
  ];

  /// The PDF of [documentTitle] that [classUuid]'s learner may open.
  Future<NotePdf?> find(String documentTitle, {String? classUuid}) async {
    for (final p in await visibleTo(classUuid)) {
      if (p.documentTitle == documentTitle) return p;
    }
    return null;
  }

  /// Deletes stored files no marker row refers to any more — after a note
  /// is deleted or unshared, or a synced subject replaced.
  Future<int> collectGarbage() async {
    final keep = {for (final p in await recorded()) p.sha256};
    final dir = await _dir();
    var removed = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final sha = name.endsWith('.pdf') ? name.substring(0, name.length - 4) : null;
      if (sha != null && keep.contains(sha)) continue;
      try {
        // Just written by an import or sync that hasn't recorded it yet.
        final age = DateTime.now().difference(await e.lastModified());
        if (age < gcGrace) continue;
        await e.delete();
        removed++;
      } catch (_) {}
    }
    return removed;
  }
}

final notePdfStoreProvider = Provider<NotePdfStore>(
  (ref) => NotePdfStore(ref.watch(dbProvider)),
);

/// This device's own notes' PDFs in one subject, by document title.
final ownNotePdfsProvider = FutureProvider.autoDispose
    .family<Map<String, NotePdf>, String>((ref, subjectId) async {
      final pdfs = await ref
          .watch(notePdfStoreProvider)
          .recorded(subjectId: subjectId, ownOnly: true);
      return {for (final p in pdfs) p.documentTitle: p};
    });

/// The PDFs a learner in [classUuid] may open: this device's own notes'
/// and those received for that class.
final visibleNotePdfsProvider = FutureProvider.autoDispose
    .family<List<NotePdf>, String?>(
      (ref, classUuid) => ref.watch(notePdfStoreProvider).visibleTo(classUuid),
    );
