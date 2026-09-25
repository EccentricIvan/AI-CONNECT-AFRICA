import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ai_connect_africa/services/projects/project_store.dart';

void main() {
  late Directory root;
  late ProjectStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('project_store_test');
    store = ProjectStore(root: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<ProjectFolder> saveSite({String title = 'My Bakery', String? id}) => store.save(
        studentId: 7,
        studentName: 'Amina',
        kind: ProjectKind.website,
        title: title,
        projectId: id,
        files: {
          'frontend/index.html': '<h1>$title</h1>',
          'backend/app/main.py': 'app = None\n',
        },
      );

  test('save creates learner/kind/project folders with a manifest', () async {
    final f = await saveSite();
    expect(f.path, p.join(root.path, 'amina-7', 'Websites', 'my-bakery'));
    expect(File(p.join(f.path, 'frontend', 'index.html')).existsSync(), isTrue);
    expect(File(p.join(f.path, ProjectManifest.fileName)).existsSync(), isTrue);
    expect(f.manifest.hasBackend, isTrue);
    expect(f.fileCount, 2);
    expect(Directory(root.path).listSync(recursive: true).where((e) => e.path.endsWith('.part')),
        isEmpty);
  });

  test('saving again with the same id rewrites the same folder and keeps extra files',
      () async {
    final first = await saveSite();
    File(p.join(first.path, 'notes.txt')).writeAsStringSync('mine');
    final second = await saveSite(title: 'My Bakery v2', id: first.manifest.id);
    expect(second.path, first.path);
    expect(second.title, 'My Bakery v2');
    expect(File(p.join(first.path, 'notes.txt')).readAsStringSync(), 'mine');
    expect(await store.list(7), hasLength(1));
  });

  test('same title twice gets a unique folder', () async {
    await saveSite();
    final b = await saveSite();
    expect(p.basename(b.path), 'my-bakery-2');
  });

  test('learner folder is found by id even after a name change', () async {
    await saveSite();
    final dir = await store.learnerDirectory(7, studentName: 'Amina Nakato');
    expect(p.basename(dir.path), 'amina-7');
  });

  test('list shows folders pasted in by hand, under the folder they sit in', () async {
    await saveSite();
    final pasted = Directory(p.join(root.path, 'amina-7', 'Applications', 'from-usb'))
      ..createSync(recursive: true);
    File(p.join(pasted.path, 'index.html')).writeAsStringSync('<p>hi</p>');
    final all = await store.list(7);
    final handMade = all.firstWhere((f) => f.folderName == 'from-usb');
    expect(handMade.kind, ProjectKind.application);
    expect(handMade.hasManifestFile, isFalse);
  });

  test('rename, duplicate, move and delete', () async {
    final f = await saveSite();
    final renamed = await store.rename(f, 'Best Bakery');
    expect(p.basename(renamed.path), 'best-bakery');
    expect(renamed.title, 'Best Bakery');

    final copy = await store.duplicate(renamed, 7);
    expect(copy.title, 'Best Bakery (copy)');
    expect(copy.manifest.id, isNot(renamed.manifest.id));

    final moved = await store.moveToKind(copy, 7, ProjectKind.application);
    expect(moved.kind, ProjectKind.application);
    expect(p.basename(p.dirname(moved.path)), 'Applications');
    expect(Directory(copy.path).existsSync(), isFalse);

    await store.delete(moved);
    final left = await store.list(7);
    expect(left.map((e) => e.title), ['Best Bakery']);
  });

  test('zip export contains every file under the project folder, without the manifest',
      () async {
    final f = await saveSite();
    await store.addFiles(f, binaryFiles: {
      'frontend/images/logo.png': Uint8List.fromList([1, 2, 3]),
    });
    final zip = ZipDecoder().decodeBytes(await store.exportZip(f));
    final names = zip.files.map((e) => e.name).toSet();
    expect(names, containsAll([
      'my-bakery/frontend/index.html',
      'my-bakery/backend/app/main.py',
      'my-bakery/frontend/images/logo.png',
    ]));
    expect(names.any((n) => n.endsWith(ProjectManifest.fileName)), isFalse);
  });

  test('export to a directory copies the folder', () async {
    final f = await saveSite();
    final dest = await Directory.systemTemp.createTemp('export_dest');
    try {
      final out = await store.exportToDirectory(f, dest.path);
      expect(File(p.join(out, 'frontend', 'index.html')).existsSync(), isTrue);
      final marked = await store.markExported(f);
      expect(marked.manifest.exportedAt, isNotNull);
    } finally {
      await dest.delete(recursive: true);
    }
  });

  test('refuses paths that escape the project folder', () async {
    expect(
      () => store.save(
        studentId: 7,
        kind: ProjectKind.website,
        title: 'Bad',
        files: {'../escape.txt': 'x'},
      ),
      throwsArgumentError,
    );
  });

  test('deleteLearner removes only that learner', () async {
    await saveSite();
    await store.save(
        studentId: 8, studentName: 'Brian', kind: ProjectKind.python, title: 'Calc',
        files: {'main.py': 'print(1)'});
    await store.deleteLearner(7);
    expect(await store.list(7), isEmpty);
    expect(await store.list(8), hasLength(1));
  });
}
