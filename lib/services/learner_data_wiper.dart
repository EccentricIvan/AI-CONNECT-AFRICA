import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/otic_database.dart';
import '../memory/session_recall_store.dart';
import 'projects/project_store.dart';

/// Deletes a learner's own data — never the shared "application resources"
/// a device's students learn from. Those live in `topic_resources`,
/// `custom_subjects`, `class_groups`, the translation cache, and
/// `sync_state` (the P2P resource-sync bookkeeping — see
/// `SelectiveSyncManager`, which pulls resources over the local network for
/// the same reason: that network carries resources, never student data).
/// None of those are touched here.
///
/// Tables wiped, all keyed by `student_id`: `students`, `session_summaries`,
/// `topic_progress`, `learning_paths`, `earned_badges`, `student_projects`,
/// `website_projects`, `app_builder_projects`, `assignments`, and
/// `chat_sessions` (plus the recall files those sessions keep in
/// `otic_sessions/`, deleted after the row is gone — see
/// `ChatSessionDao.deleteForStudent`). [wipedTableNames] names them so a
/// test can assert every per-student table in the schema is accounted for.
///
/// Also clears the `active_student_id` pref, and repoints or clears
/// `student_name` — the router's own fast-path "onboarding done" flag (see
/// `_onboardingRedirect` in `app_router.dart`), which it checks *before*
/// the database. It must never keep naming a learner this call just
/// deleted (repointed at another surviving learner, or cleared once none
/// remain) — leaving it stale would either bounce a fresh `/onboarding`
/// visit back to home with the wrong name still saved, or make
/// `createProfile`'s own "update instead of insert" guard silently resurrect
/// a name on a row that no longer exists.
///
/// Also deletes this learner's saved certificate PDFs from
/// `otic_certificates/` — see `_deleteCertificatesFor`'s own doc for why
/// that match is by (sanitized) name rather than student id, and its
/// limitation.
class LearnerDataWiper {
  LearnerDataWiper(
    this._db, {
    SessionRecallStore? recallStore,
    Future<Directory> Function()? certificatesDir,
    ProjectStore? projectStore,
  })  : _recallStore = recallStore ?? SessionRecallStore(),
        _certificatesDir = certificatesDir ?? _defaultCertificatesDir,
        _projects = projectStore ?? ProjectStore();

  final OticDatabase _db;
  final SessionRecallStore _recallStore;

  /// Project folders (Create → Projects) are per-learner files on disk, not
  /// rows — removed after the rows commit, like the recall files.
  final ProjectStore _projects;
  final Future<Directory> Function() _certificatesDir;

  static Future<Directory> _defaultCertificatesDir() async {
    final dir = await getApplicationDocumentsDirectory();
    // Same location CertificateGenerator.generate writes to.
    return Directory('${dir.path}${Platform.pathSeparator}otic_certificates');
  }

  static const wipedTableNames = {
    'students',
    'session_summaries',
    'topic_progress',
    'learning_paths',
    'earned_badges',
    'student_projects',
    'website_projects',
    'app_builder_projects',
    'assignments',
    'chat_sessions',
  };

  /// Deletes one learner and everything scoped to them — the rest of a
  /// shared device's other learners are untouched.
  Future<void> wipeStudent(int studentId) async {
    // Read before any row is gone — the deleted learner's own name is
    // needed below to find their certificate PDFs, and the full roster is
    // needed to tell their files apart from a same-prefixed learner's (see
    // _deleteCertificatesFor).
    final roster = await _db.studentDao.getAllStudents();
    final matches = roster.where((s) => s.id == studentId);
    final studentName = matches.isEmpty ? null : matches.first.name;
    final allNames = roster.map((s) => s.name).toList();

    // One transaction: a crash partway through row deletes must not leave
    // a student's profile gone while their badges/progress rows (or vice
    // versa) survive as orphans — either the whole wipe lands or none of
    // it does. Recall files and prefs are outside it because file/prefs IO
    // cannot be rolled back with the DB anyway; they run only once the
    // deletes have actually committed.
    final sessionIds =
        await _db.transaction(() => _deleteRowsForStudent(studentId));
    for (final id in sessionIds) {
      await _recallStore.delete(id);
    }
    if (studentName != null) {
      await _deleteCertificatesFor(studentName, allNames);
    }
    await _deleteProjectsFor(studentId);

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      // Per-student curriculum-lesson checkmarks — see
      // LessonProgress.markCompleteFor. The older shared, unscoped
      // `lesson_done_<subject>_<unit>_<lesson>` keys aren't attributable to
      // one learner on a shared device, so a single-student wipe leaves
      // them alone; wipeAll below clears those too, once no student remains
      // for them to (wrongly) apply to.
      if (key.startsWith('lesson_done_s${studentId}_')) {
        await prefs.remove(key);
      }
    }
    if (prefs.getInt('active_student_id') == studentId) {
      await prefs.remove('active_student_id');
    }
    // The router's own fast-path "onboarding done" check reads this name,
    // not the database (see _onboardingRedirect in app_router.dart), so it
    // must never keep naming a learner this call just deleted — that is
    // "data about the student" surviving their own wipe, even though
    // nothing displays the flag itself. With learners still on the device
    // it is repointed at whichever one the app now resolves as active,
    // mirroring resolveActiveStudent(db) without importing db_provider.dart
    // (which imports this file); with none left it is cleared, same as
    // wipeAll.
    final remaining = await _db.studentDao.getAllStudents();
    if (remaining.isEmpty) {
      await prefs.remove('student_name');
    } else {
      // Mirrors resolveActiveStudent(db)'s own fallback exactly (without
      // importing db_provider.dart, which imports this file): a stale
      // active_student_id — e.g. from a learner deleted before this wiper
      // existed, whose id was never cleared from prefs — must not read as
      // "no one's active" and clear the flag while learners remain. With
      // at least one learner left, getActiveStudent() always finds one.
      final activeId = prefs.getInt('active_student_id');
      final byId = activeId != null
          ? await _db.studentDao.getStudentById(activeId)
          : null;
      final active = byId ?? await _db.studentDao.getActiveStudent();
      if (active != null) {
        await prefs.setString('student_name', active.name);
      } else {
        await prefs.remove('student_name');
      }
    }
  }

  /// Deletes every learner on this device and everything scoped to them.
  /// Application resources (see the class doc) are untouched, so a device
  /// wiped this way still has its curriculum, teacher notes and classes —
  /// only the learners themselves are gone, same as a fresh install's first
  /// onboarding but without re-transferring any resource.
  Future<void> wipeAll() async {
    final students = await _db.studentDao.getAllStudents();
    for (final student in students) {
      // One transaction per student, not one for the whole device: a crash
      // partway through wiping student #7 of 20 must not undo the 6 that
      // already fully committed, and per-student atomicity is all the
      // guarantee wipeStudent above already promises on its own.
      final sessionIds =
          await _db.transaction(() => _deleteRowsForStudent(student.id));
      for (final id in sessionIds) {
        await _recallStore.delete(id);
      }
      await _deleteProjectsFor(student.id);
    }
    // Every learner is gone at this point, so unlike wipeStudent there is
    // no name-collision risk to resolve — every certificate PDF in the
    // folder is deleted outright. This also sweeps up any certificate
    // orphaned by a deletion made before this wiper existed (the old Admin
    // "Delete profile" never touched this folder at all).
    await _deleteAllCertificates();

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key == 'active_student_id' || key.startsWith('lesson_done_')) {
        await prefs.remove(key);
      }
    }
    // Same reasoning as wipeStudent above — cleared unconditionally here
    // since no learner survives a wipeAll for it to describe.
    await prefs.remove('student_name');
  }

  Future<Set<String>> _deleteRowsForStudent(int studentId) async {
    final sessionIds = await _db.chatSessionDao.deleteForStudent(studentId);
    await (_db.delete(_db.sessionSummaries)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.topicProgress)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.learningPaths)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.earnedBadges)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.studentProjects)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.websiteProjects)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.appBuilderProjects)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await (_db.delete(_db.assignments)
          ..where((t) => t.studentId.equals(studentId)))
        .go();
    await _db.studentDao.deleteStudent(studentId);
    return sessionIds;
  }

  Future<void> _deleteProjectsFor(int studentId) async {
    try {
      await _projects.deleteLearner(studentId);
    } catch (_) {
      // Best-effort, same as certificates: a folder open in Explorer must
      // not fail a wipe whose rows already committed.
    }
  }

  static String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  /// Deletes this learner's saved certificate PDFs from `otic_certificates/`
  /// (see `CertificateGenerator.generate` and `CertificatesScreen`).
  ///
  /// Best-effort by name, not by student id: certificate files carry no
  /// student_id (there is no certificates table — `CertificatesScreen`
  /// lists the folder directly), only a filename built from
  /// `${sanitizedName}_${sanitizedTopic}_${timestamp}.pdf`. A plain
  /// `${safeName}_` prefix match is not safe on its own — "John"'s prefix
  /// also matches "John_Paul_...", so [otherNames] (every learner currently
  /// on the device, deleted one included) is used to find, for each
  /// candidate file, the *longest* matching learner name; the file is only
  /// deleted if that longest match is this learner. Two learners who
  /// sanitize to the exact same name (including a name written only in a
  /// non-Latin script, which sanitizes to nothing but underscores) can't be
  /// told apart at all — their files are left for a `wipeAll` instead,
  /// which needs no name matching. This is a real limitation of how
  /// certificates are stored today (there's no per-student index), same
  /// reason `CertificatesScreen` itself lists every saved file with no
  /// per-student filtering at all.
  Future<void> _deleteCertificatesFor(
    String studentName,
    List<String> otherNames,
  ) async {
    final safeName = _sanitizeName(studentName);
    if (!RegExp(r'[a-zA-Z0-9]').hasMatch(safeName)) return;
    final allSafeNames = otherNames.map(_sanitizeName).toList();
    if (allSafeNames.where((s) => s == safeName).length > 1) {
      return; // Ambiguous — another learner sanitizes to the same name.
    }

    try {
      final certsDir = await _certificatesDir();
      if (!await certsDir.exists()) return;
      await for (final entry in certsDir.list()) {
        if (entry is! File) continue;
        final base = entry.uri.pathSegments.last;
        if (!base.endsWith('.pdf')) continue;
        if (!base.startsWith('${safeName}_')) continue;
        final longestMatch = allSafeNames
            .where((s) => s.isNotEmpty && base.startsWith('${s}_'))
            .fold<String>('', (best, s) => s.length > best.length ? s : best);
        if (longestMatch == safeName) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Best-effort cleanup — a locked/missing file must not fail the wipe
      // the student rows themselves have already committed.
    }
  }

  /// Deletes every certificate PDF, unconditionally — see [wipeAll]'s call
  /// site for why no name matching is needed here.
  Future<void> _deleteAllCertificates() async {
    try {
      final certsDir = await _certificatesDir();
      if (!await certsDir.exists()) return;
      await for (final entry in certsDir.list()) {
        if (entry is File && entry.path.endsWith('.pdf')) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Best-effort cleanup, same reasoning as _deleteCertificatesFor.
    }
  }
}
