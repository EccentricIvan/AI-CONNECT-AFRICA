import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ai_core/model/model_locations.dart';
import 'session_recall.dart';

/// One tiny JSON file per chat session, beside the student database.
///
/// The sidebar never reads this store to build its list — that comes from the
/// `chat_sessions` index table, which is a cheap indexed query. Files are read
/// only when a specific chat is reopened, so listing stays fast no matter how
/// many sessions accumulate.
///
/// Fully offline and portable: the folder can be copied to a USB stick with
/// the database and moved to another device.
class SessionRecallStore {
  SessionRecallStore({Directory? directory}) : _override = directory;

  final Directory? _override;
  Directory? _dir;

  static const _folderName = 'otic_sessions';

  Future<Directory> _directory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = _override ??
        Directory(p.join((await resolveAppStorageDirectory()).path, _folderName));
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return _dir = base;
  }

  /// Session ids are also filenames, so refuse anything that could climb out
  /// of the folder. Ids we mint are already safe; this guards ids that came
  /// back from the database after a manual edit or a partial restore.
  static bool _safeId(String id) =>
      id.isNotEmpty &&
      id.length <= 64 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  Future<File?> _fileFor(String id) async {
    if (!_safeId(id)) return null;
    return File(p.join((await _directory()).path, '$id.json'));
  }

  /// Mint a sortable, filename-safe session id.
  static String newSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = Random().nextInt(1 << 32).toRadixString(36);
    return 's_${now}_$rand';
  }

  /// Write [recall] to disk, replacing any previous version.
  ///
  /// Writes to a temp file and renames so a crash mid-write cannot leave a
  /// half-parsed file in place of a good one. If the rename is refused (some
  /// Windows setups hold a transient lock on the destination) it falls back to
  /// writing directly — a torn write costs one session's recall, and losing
  /// that is better than losing the turn.
  Future<bool> save(SessionRecall recall) async {
    try {
      final target = await _fileFor(recall.id);
      if (target == null) return false;
      final bytes = recall.encode();
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(bytes, flush: true);
      try {
        await tmp.rename(target.path);
      } on FileSystemException {
        try {
          if (await target.exists()) await target.delete();
          await tmp.rename(target.path);
        } on FileSystemException {
          await target.writeAsString(bytes, flush: true);
          if (await tmp.exists()) await tmp.delete();
        }
      }
      return true;
    } catch (e) {
      debugPrint('session recall: save failed for ${recall.id}: $e');
      return false;
    }
  }

  /// Read one session back. Null means missing, damaged, or an unknown
  /// format version — all of which callers treat the same way.
  Future<SessionRecall?> load(String id) async {
    try {
      final file = await _fileFor(id);
      if (file == null || !await file.exists()) return null;
      return SessionRecall.decode(await file.readAsString());
    } catch (e) {
      debugPrint('session recall: load failed for $id: $e');
      return null;
    }
  }

  Future<void> delete(String id) async {
    try {
      final file = await _fileFor(id);
      if (file == null) return;
      if (await file.exists()) await file.delete();
      final tmp = File('${file.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
    } catch (e) {
      debugPrint('session recall: delete failed for $id: $e');
    }
  }

  /// Remove recall files whose id is not in [keepIds].
  ///
  /// The index table is the source of truth for what exists, so this clears
  /// files orphaned by a deleted student or an interrupted write.
  Future<int> pruneExcept(Set<String> keepIds) async {
    var removed = 0;
    try {
      final dir = await _directory();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.endsWith('.json.tmp')) {
          await entity.delete();
          continue;
        }
        if (!name.endsWith('.json')) continue;
        final id = name.substring(0, name.length - '.json'.length);
        if (keepIds.contains(id)) continue;
        await entity.delete();
        removed++;
      }
    } catch (e) {
      debugPrint('session recall: prune failed: $e');
    }
    return removed;
  }
}
