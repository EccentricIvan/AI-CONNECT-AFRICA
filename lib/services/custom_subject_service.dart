import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../curriculum/curriculum_models.dart';
import '../curriculum/curriculum_provider.dart';
import '../curriculum/subject_style.dart';
import '../db/otic_database.dart';
import '../db/providers/db_provider.dart';
import 'offline_storage_service.dart';
import 'resource_text_extractor.dart';

/// Subjects a teacher created, and the bridge that makes them browsable.
///
/// ## What "alongside" means here
///
/// The 16 bundled subjects keep working exactly as before — this service never
/// reads, writes or shadows `assets/curriculum/*.json`, and [CurriculumService]
/// is untouched. A custom subject is simply appended to the browse grid.
///
/// ## Where a custom subject's content comes from
///
/// A bundled subject's teaching content is its JSON. A custom subject has no
/// JSON: its content is the notes teachers uploaded into it, shown one per
/// file on the subject's Notes tab, with a Quiz written from them — see
/// [buildCustomSubject].
class CustomSubjectService {
  CustomSubjectService(this._db);

  final OticDatabase _db;

  /// Ids that may not be taken, because a bundled subject already owns them.
  ///
  /// Without this a teacher could create a second "Chemistry" whose slug
  /// collided with the bundled one; the grid would show two cards and the
  /// router would resolve `/learn/subject/chemistry` to whichever the merge
  /// happened to prefer.
  static const reservedIds = CurriculumService.bundledSubjectIds;

  /// Creates a subject from a teacher-typed [name], with a card icon and
  /// colour picked from the name ([subjectStyleFor]).
  ///
  /// Returns the new subject id, or a [CustomSubjectError] describing why not
  /// — an empty name, or a name that collides with something that exists.
  Future<CustomSubjectResult> create({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const CustomSubjectResult.failed('Give the subject a name.');
    }
    if (trimmed.length > 60) {
      return const CustomSubjectResult.failed('That name is too long.');
    }

    var id = normalizeSubjectId(trimmed);
    if (id.isEmpty) {
      return const CustomSubjectResult.failed(
        'Use letters or numbers in the subject name.',
      );
    }
    if (reservedIds.contains(id)) {
      if (!(await removedBuiltIns()).contains(id)) {
        return CustomSubjectResult.failed(
          'There is already a subject called "$trimmed".',
        );
      }
      // The built-in was removed: the name is free, but its id stays the
      // built-in's (lesson progress and class sync key on it).
      id = '${id}_school';
    }
    if (await _db.customSubjectDao.exists(id)) {
      return CustomSubjectResult.failed(
        'You already have a subject called "$trimmed".',
      );
    }

    try {
      final style = subjectStyleFor(
        trimmed,
        taken: [for (final s in await list()) s.color],
      );
      await _db.customSubjectDao.insertSubject(
        subjectId: id,
        name: trimmed,
        icon: style.icon,
        color: style.color,
      );
      return CustomSubjectResult(subjectId: id);
    } catch (e) {
      debugPrint('createSubject failed: $e');
      return const CustomSubjectResult.failed(
        'That subject could not be saved.',
      );
    }
  }

  Future<List<CustomSubject>> list() async {
    try {
      return await _db.customSubjectDao.all();
    } catch (e) {
      debugPrint('list custom subjects failed: $e');
      return const [];
    }
  }

  Future<CustomSubject?> find(String subjectId) async {
    try {
      return await _db.customSubjectDao.bySubjectId(
        normalizeSubjectId(subjectId),
      );
    } catch (_) {
      return null;
    }
  }

  /// Subjects are the Admin's records: only `AdminService` renames and
  /// deletes them.
  Future<void> rename(String subjectId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = normalizeSubjectId(subjectId);
    final style = subjectStyleFor(
      trimmed,
      taken: [
        for (final s in await list())
          if (s.subjectId != id) s.color,
      ],
    );
    await _db.customSubjectDao.rename(id, trimmed, style: style);
  }

  /// Built-in subjects the Admin removed.
  Future<Set<String>> removedBuiltIns() async {
    try {
      return {
        for (final r in await _db.select(_db.removedSubjects).get())
          r.subjectId,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Hides built-in [subjectId] and deletes what was uploaded into it.
  Future<void> removeBuiltIn(String subjectId) async {
    final id = normalizeSubjectId(subjectId);
    if (!reservedIds.contains(id)) return;
    await _db.transaction(() async {
      await _db.topicResourceDao.deleteBySubject(id);
      await _db
          .into(_db.removedSubjects)
          .insertOnConflictUpdate(
            RemovedSubjectsCompanion.insert(
              subjectId: id,
              removedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
    });
  }

  /// Shows built-in [subjectId] again.
  Future<void> restoreBuiltIn(String subjectId) =>
      (_db.delete(_db.removedSubjects)
            ..where((t) => t.subjectId.equals(normalizeSubjectId(subjectId))))
          .go();

  /// Removes a subject **and** everything uploaded into it, in one
  /// transaction — a subject that vanished while its material stayed behind
  /// would leave rows no screen could ever reach or delete.
  Future<void> delete(String subjectId) async {
    final id = normalizeSubjectId(subjectId);
    await _db.transaction(() async {
      await _db.topicResourceDao.deleteBySubject(id);
      await _db.customSubjectDao.deleteSubject(id);
    });
  }

  /// Builds the browsable [Subject] for a custom subject, from its resources.
  Future<Subject?> buildSubject(String subjectId) async {
    final id = normalizeSubjectId(subjectId);
    final row = await find(id);
    if (row == null) return null;
    return buildCustomSubject(row);
  }
}

/// Assembles a [Subject] from a custom subject row.
///
/// A school's subject has no built-in lessons: its content is the notes
/// the teachers uploaded, one per file, on the subject's Notes tab. It used
/// to list every section of every file as a "lesson", which read as loose
/// fragments and opened a lesson screen that only knows the built-ins.
Subject buildCustomSubject(CustomSubject row) {
  const units = <Unit>[];
  final style = shownSubjectStyle(row.name, row.icon, row.color);
  return Subject(
    id: row.subjectId,
    name: row.name,
    icon: style.icon,
    color: style.color,
    units: units,
  );
}

/// [title] ("Document — Section") without a section part that came out of
/// the PDF as unreadable symbols. Notes stored before headings were checked
/// still carry those.
String cleanLessonTitle(String title) {
  final cut = title.lastIndexOf(' — ');
  if (cut < 0) return title;
  final section = dropUnreadableLines(title.substring(cut + 3)).trim();
  return looksLikeTitleText(section)
      ? '${title.substring(0, cut)} — $section'
      : title.substring(0, cut);
}

/// Result of a create attempt.
class CustomSubjectResult {
  const CustomSubjectResult({required this.subjectId}) : error = null;
  const CustomSubjectResult.failed(this.error) : subjectId = null;

  final String? subjectId;
  final String? error;

  bool get ok => subjectId != null;
}

// ── Providers ────────────────────────────────────────────────────────────

final customSubjectServiceProvider = Provider<CustomSubjectService>((ref) {
  return CustomSubjectService(ref.watch(dbProvider));
});

final customSubjectsProvider = FutureProvider<List<CustomSubject>>((ref) {
  return ref.watch(customSubjectServiceProvider).list();
});

/// Built-in subject ids the Admin removed.
final removedSubjectsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(customSubjectServiceProvider).removedBuiltIns();
});

/// Every subject the app can show: the bundled ones the Admin kept, then the
/// school's own.
///
/// This is the provider the browse grid watches. [allSubjectsProvider] — the
/// bundled-only list — is left exactly as it was, so anything that genuinely
/// wants "the shipped curriculum" still has it.
final mergedSubjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final bundled = await ref.watch(allSubjectsProvider.future);
  final custom = await ref.watch(customSubjectsProvider.future);
  final removed = await ref.watch(removedSubjectsProvider.future);

  final built = [for (final row in custom) buildCustomSubject(row)];
  return [
    for (final s in bundled)
      if (!removed.contains(s.id)) s,
    ...built,
  ];
});

/// One subject by id, bundled or custom.
///
/// The router hands screens a bare id, so resolution has to try both stores.
/// Bundled wins on a tie, which cannot happen anyway because
/// [CustomSubjectService.reservedIds] refuses those ids at creation. A
/// built-in the Admin removed resolves to nothing.
final subjectByIdProvider = FutureProvider.family<Subject?, String>((
  ref,
  subjectId,
) async {
  final removed = await ref.watch(removedSubjectsProvider.future);
  if (removed.contains(subjectId)) return null;
  final bundled = await ref.watch(curriculumServiceProvider).load(subjectId);
  if (bundled != null) return bundled;
  return ref.watch(customSubjectServiceProvider).buildSubject(subjectId);
});
