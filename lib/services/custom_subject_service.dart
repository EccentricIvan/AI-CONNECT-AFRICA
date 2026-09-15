import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../curriculum/curriculum_models.dart';
import '../curriculum/curriculum_provider.dart';
import '../db/daos/topic_resource_dao.dart';
import '../db/otic_database.dart';
import '../db/providers/db_provider.dart';
import 'offline_storage_service.dart';

/// Subjects a teacher created, and the bridge that makes them browsable.
///
/// ## What "alongside" means here
///
/// The 16 bundled subjects keep working exactly as before — this service never
/// reads, writes or shadows `assets/curriculum/*.json`, and [CurriculumService]
/// is untouched. A custom subject is simply appended to the browse grid.
///
/// ## Where a custom subject's lessons come from
///
/// A bundled subject's teaching content is its JSON. A custom subject has no
/// JSON, so its content is **synthesized from the resources the teacher
/// uploaded** — see [buildCustomSubject]. Each imported document section
/// becomes a [Lesson], grouped into a [Unit] per school term. That is what lets
/// a teacher-made subject flow through the existing browse → open → read
/// screens without a single new widget.
class CustomSubjectService {
  CustomSubjectService(this._db, this._storage);

  final OticDatabase _db;
  final OfflineStorageService _storage;

  /// Ids that may not be taken, because a bundled subject already owns them.
  ///
  /// Without this a teacher could create a second "Chemistry" whose slug
  /// collided with the bundled one; the grid would show two cards and the
  /// router would resolve `/learn/subject/chemistry` to whichever the merge
  /// happened to prefer.
  static const reservedIds = CurriculumService.bundledSubjectIds;

  /// Creates a subject from a teacher-typed [name].
  ///
  /// Returns the new subject id, or a [CustomSubjectError] describing why not
  /// — an empty name, or a name that collides with something that exists.
  Future<CustomSubjectResult> create({
    required String name,
    String icon = 'menu_book',
    String color = '#4F46E5',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const CustomSubjectResult.failed('Give the subject a name.');
    }
    if (trimmed.length > 60) {
      return const CustomSubjectResult.failed('That name is too long.');
    }

    final id = normalizeSubjectId(trimmed);
    if (id.isEmpty) {
      return const CustomSubjectResult.failed(
        'Use letters or numbers in the subject name.',
      );
    }
    if (reservedIds.contains(id)) {
      return CustomSubjectResult.failed(
        'There is already a subject called "$trimmed".',
      );
    }
    if (await _db.customSubjectDao.exists(id)) {
      return CustomSubjectResult.failed(
        'You already have a subject called "$trimmed".',
      );
    }

    try {
      await _db.customSubjectDao.insertSubject(
        subjectId: id,
        name: trimmed,
        icon: icon,
        color: color,
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

  Future<void> rename(String subjectId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _db.customSubjectDao.rename(normalizeSubjectId(subjectId), trimmed);
  }

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
    final resources = await _storage.listResources(subjectId: id);
    return buildCustomSubject(row, resources);
  }
}

/// Assembles a [Subject] from a custom subject row and its uploaded material.
///
/// Pure so it can be tested without a database. Units are school terms, in
/// order, and only terms that actually have material appear — an empty
/// "Term 3" heading tells a student nothing.
Subject buildCustomSubject(
  CustomSubject row,
  List<ResourceSummary> resources,
) {
  const termOrder = [0, 1, 2, 3];
  const termNames = {
    0: 'All terms',
    1: 'Term 1',
    2: 'Term 2',
    3: 'Term 3',
  };

  final units = <Unit>[];
  for (final term in termOrder) {
    final inTerm = resources.where((r) => r.termMarker == term).toList();
    if (inTerm.isEmpty) continue;
    units.add(
      Unit(
        title: termNames[term] ?? 'All terms',
        lessons: [
          for (final r in inTerm)
            Lesson(
              title: r.resourceTitle,
              // The card and reader show the title; the body is retrieved from
              // topic_resources when the student opens it, so the whole
              // document is not held in memory just to list it.
              content: '',
            ),
        ],
      ),
    );
  }

  return Subject(
    id: row.subjectId,
    name: row.name,
    icon: row.icon,
    color: row.color,
    units: units,
  );
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
  return CustomSubjectService(
    ref.watch(dbProvider),
    ref.watch(offlineStorageServiceProvider),
  );
});

final customSubjectsProvider = FutureProvider<List<CustomSubject>>((ref) {
  return ref.watch(customSubjectServiceProvider).list();
});

/// Every subject the app can show: the 16 bundled ones, then the teacher's.
///
/// This is the provider the browse grid watches. [allSubjectsProvider] — the
/// bundled-only list — is left exactly as it was, so anything that genuinely
/// wants "the shipped curriculum" still has it.
final mergedSubjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final bundled = await ref.watch(allSubjectsProvider.future);
  final custom = await ref.watch(customSubjectsProvider.future);
  final storage = ref.watch(offlineStorageServiceProvider);

  final built = <Subject>[];
  for (final row in custom) {
    final resources = await storage.listResources(subjectId: row.subjectId);
    built.add(buildCustomSubject(row, resources));
  }
  return [...bundled, ...built];
});

/// One subject by id, bundled or custom.
///
/// The router hands screens a bare id, so resolution has to try both stores.
/// Bundled wins on a tie, which cannot happen anyway because
/// [CustomSubjectService.reservedIds] refuses those ids at creation.
final subjectByIdProvider =
    FutureProvider.family<Subject?, String>((ref, subjectId) async {
  final bundled = await ref.watch(curriculumServiceProvider).load(subjectId);
  if (bundled != null) return bundled;
  return ref.watch(customSubjectServiceProvider).buildSubject(subjectId);
});
