import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import 'legacy_project_sync.dart';
import 'project_store.dart';

export 'project_store.dart';

final projectStoreProvider = Provider<ProjectStore>((ref) => ProjectStore());

/// Every project folder the learner has, newest first. Re-scans the disk,
/// so changes made in Explorer show up on the next refresh.
final studentProjectFoldersProvider =
    FutureProvider.family<List<ProjectFolder>, int>((ref, studentId) async {
  final store = ref.watch(projectStoreProvider);
  final db = ref.watch(dbProvider);
  final student = await db.studentDao.getStudentById(studentId);
  // Rows saved by the Block canvas / guided Create chat (and older App
  // builder saves) get their folders here, so every creation is listed.
  await LegacyProjectSync(db, store).sync(studentId, studentName: student?.name);
  return store.list(studentId);
});

/// Outcome of [saveCreation] for the builder's snackbar.
class SavedCreation {
  const SavedCreation(this.folder, {required this.isNew});
  final ProjectFolder folder;
  final bool isNew;

  /// "Projects › Websites › my-bakery"
  String get breadcrumb =>
      'Projects › ${folder.kind.folderName} › ${folder.folderName}';
}

/// The one save path every builder uses: writes the folder for the active
/// learner, awards badges on a first save, and refreshes Projects and
/// Achievements. Returns null when there is no learner to save for.
Future<SavedCreation?> saveCreation(
  WidgetRef ref, {
  required ProjectKind kind,
  required String title,
  required Map<String, String> files,
  Map<String, Uint8List> binaryFiles = const {},
  String? projectId,
  String source = '',
  String template = '',
  String templateName = '',
  List<String> features = const [],
  Map<String, String> answers = const {},
}) async {
  final student = await ref.read(activeStudentProvider.future);
  if (student == null) return null;
  final store = ref.read(projectStoreProvider);
  final existed = projectId != null && await store.findById(student.id, projectId) != null;
  final folder = await store.save(
    studentId: student.id,
    studentName: student.name,
    kind: kind,
    title: title,
    files: files,
    binaryFiles: binaryFiles,
    projectId: projectId,
    source: source,
    template: template,
    templateName: templateName,
    features: features,
    answers: answers,
  );
  if (!existed) {
    await ref
        .read(badgeServiceProvider)
        .onProjectSaved(student.id, fullStack: folder.manifest.hasBackend);
  }
  ref.invalidate(studentProjectFoldersProvider(student.id));
  return SavedCreation(folder, isNew: !existed);
}
