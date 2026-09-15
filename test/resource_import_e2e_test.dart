import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/tables/topic_resources_table.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/offline_rag_service.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/resource_import_service.dart';

Future<Uint8List> buildPdf(List<String> paragraphs) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [for (final p in paragraphs) pw.Paragraph(text: p)],
      ),
    ),
  );
  return Uint8List.fromList(await doc.save());
}

void main() {
  late OticDatabase db;
  late OfflineStorageService storage;
  late OfflineRagService rag;
  late ResourceImportService importer;
  late CustomSubjectService subjects;

  setUp(() {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    storage = OfflineStorageService(db);
    rag = OfflineRagService(storage);
    importer = ResourceImportService(storage);
    subjects = CustomSubjectService(db, storage);
  });

  tearDown(() => db.close());

  // ── The whole point, end to end ───────────────────────────────────────
  //
  // Teacher creates a subject that is not in the hardcoded list, uploads a
  // PDF, and a student's question retrieves it. Every step uses the spelling
  // the layer above actually passes, not a spelling the test chose.
  group('teacher creates a subject and uploads a PDF', () {
    test('the PDF becomes retrievable knowledge', () async {
      final created = await subjects.create(name: 'Senior 4 Chemistry');
      expect(created.ok, isTrue, reason: created.error ?? '');
      final subjectId = created.subjectId!;
      expect(subjectId, 'senior_4_chemistry');

      final pdf = await buildPdf([
        'Neutralisation is the reaction between an acid and a base. '
            'It always produces a salt together with water.',
        'Litmus paper turns red in acid conditions and blue in alkaline ones.',
      ]);

      final report = await importer.importBytes(
        fileName: 'Acid-Base Balances.pdf',
        bytes: pdf,
        subjectId: subjectId,
        termMarker: 2,
      );

      expect(report.ok, isTrue, reason: report.failure ?? '');
      expect(report.format, 'pdf');
      expect(report.wordCount, greaterThan(20));

      // A student asks, using the subject id the teacher screen created.
      final context = await rag.retrieveContextForQuery(
        'What does neutralisation produce?',
        subjectId,
        'Acid-Base Balances',
      );

      expect(context, isNotEmpty);
      expect(context.toLowerCase(), contains('salt'));
    });

    test('a created subject is browsable and shows its uploads as lessons',
        () async {
      final created = await subjects.create(name: 'Local Farming');
      final subjectId = created.subjectId!;

      await importer.importText(
        title: 'Soil Preparation',
        content: 'Turn the soil before the first rains so water soaks in. '
            'Add compost to return nutrients the last crop removed.',
        subjectId: subjectId,
        termMarker: 1,
      );

      final subject = await subjects.buildSubject(subjectId);

      expect(subject, isNotNull);
      expect(subject!.name, 'Local Farming');
      expect(subject.id, subjectId);
      expect(subject.units, hasLength(1));
      expect(subject.units.single.title, 'Term 1');
      expect(subject.totalLessons, 1);
      expect(subject.units.single.lessons.single.title, 'Soil Preparation');
    });

    test('uploads group into units by term', () async {
      final subjectId = (await subjects.create(name: 'Civics')).subjectId!;
      await importer.importText(
        title: 'Term One Notes',
        content: 'A long enough note about local government structures here.',
        subjectId: subjectId,
        termMarker: 1,
      );
      await importer.importText(
        title: 'Term Two Notes',
        content: 'A long enough note about national government structures.',
        subjectId: subjectId,
        termMarker: 2,
      );

      final subject = await subjects.buildSubject(subjectId);
      expect(subject!.units.map((u) => u.title), ['Term 1', 'Term 2']);
    });
  });

  // ── Subject creation rules ────────────────────────────────────────────
  group('creating subjects', () {
    test('a bundled subject id cannot be taken over', () async {
      final result = await subjects.create(name: 'Chemistry');
      expect(result.ok, isFalse);
      expect(result.error, contains('already a subject'));
    });

    test('the same custom name cannot be created twice', () async {
      expect((await subjects.create(name: 'Fishing')).ok, isTrue);
      final second = await subjects.create(name: 'fishing');
      expect(second.ok, isFalse);
      expect(second.error, contains('already have'));
    });

    test('an empty or symbol-only name is refused', () async {
      expect((await subjects.create(name: '   ')).ok, isFalse);
      expect((await subjects.create(name: '!!!')).ok, isFalse);
    });

    test('deleting a subject removes its uploaded material too', () async {
      final subjectId = (await subjects.create(name: 'Beekeeping')).subjectId!;
      await importer.importText(
        title: 'Hive Notes',
        content: 'Bees need shade and a steady water source close to the hive.',
        subjectId: subjectId,
      );
      expect(await storage.hasAnyResources(), isTrue);

      await subjects.delete(subjectId);

      expect(await subjects.find(subjectId), isNull);
      expect(await storage.hasAnyResources(), isFalse,
          reason: 'orphaned rows would be unreachable and undeletable');
    });

    test('custom subjects do not disturb the bundled ids', () async {
      await subjects.create(name: 'Senior 4 Chemistry');
      expect(CustomSubjectService.reservedIds, contains('chemistry'));
      expect(CustomSubjectService.reservedIds, isNot(contains('senior_4_chemistry')));
    });
  });

  // ── Auto-sectioning ───────────────────────────────────────────────────
  //
  // "Convert them to the best way it can retrieve them": a chapter is not one
  // topic, so the document's own headings become the retrieval keys.
  group('automatic sectioning', () {
    test('headings become separate retrievable topics', () async {
      final subjectId = (await subjects.create(name: 'Biology Notes')).subjectId!;

      const doc = '''
PHOTOSYNTHESIS
Plants convert light energy into chemical energy stored as glucose.
Chlorophyll in the leaves absorbs light most strongly in blue and red.

RESPIRATION
Respiration releases the energy stored in glucose for the cell to use.
It happens in the mitochondria and consumes oxygen in the process.
''';

      final report = await importer.importText(
        title: 'Unit 1',
        content: doc,
        subjectId: subjectId,
      );
      expect(report.ok, isTrue);

      // Imported as one note here, so section splitting is exercised directly.
      final sections = splitIntoSections(doc, fallbackTitle: 'Unit 1');
      expect(sections.map((s) => s.title),
          containsAll(['PHOTOSYNTHESIS', 'RESPIRATION']));
    });

    test('a file with headings indexes each section under its own topic',
        () async {
      final subjectId = (await subjects.create(name: 'Landforms Class')).subjectId!;
      const doc = '''
RIVERS AND LAKES
A river carries water from high ground toward the sea across the land.
Lakes form where water collects in a basin with no quick outlet to escape.

MOUNTAINS AND VALLEYS
Mountains rise where the crust is pushed upward over very long periods.
Valleys are carved between them by rivers and by moving ice over time.
''';

      await importer.importBytes(
        fileName: 'Landforms.txt',
        bytes: Uint8List.fromList(doc.codeUnits),
        subjectId: subjectId,
      );

      // Each heading is independently retrievable.
      final rivers = await rag.retrieveContextForQuery(
        'How do lakes form?',
        subjectId,
        'RIVERS AND LAKES',
      );
      expect(rivers.toLowerCase(), contains('basin'));

      final mountains = await rag.retrieveContextForQuery(
        'What carves valleys?',
        subjectId,
        'MOUNTAINS AND VALLEYS',
      );
      expect(mountains.toLowerCase(), contains('valleys'));
    });

    test('a document with no headings becomes one section', () {
      final sections = splitIntoSections(
        'Just a page of plain notes with no headings anywhere in the text. '
        'It runs on for a while but never introduces a title of any kind.',
        fallbackTitle: 'My Notes',
      );
      expect(sections, hasLength(1));
      expect(sections.single.title, 'My Notes');
    });

    test('prose is not mistaken for a heading', () {
      expect(looksLikeHeading('PHOTOSYNTHESIS'), isTrue);
      expect(looksLikeHeading('Chapter 4 Acids'), isTrue);
      expect(looksLikeHeading('## Respiration'), isTrue);
      expect(looksLikeHeading('3.1 Neutralisation'), isTrue);

      expect(
        looksLikeHeading(
          'Plants convert light energy into chemical energy stored as glucose.',
        ),
        isFalse,
      );
      expect(looksLikeHeading('It happens in the mitochondria,'), isFalse);
      expect(looksLikeHeading(''), isFalse);
    });
  });

  // ── Honest failure ────────────────────────────────────────────────────
  group('import failures are reported, not swallowed', () {
    test('a scanned-style PDF names the reason', () async {
      final report = await importer.importBytes(
        fileName: 'scan.pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
        subjectId: 'anything',
      );
      expect(report.ok, isFalse);
      expect(report.failure, contains('scan'));
    });

    test('an unsupported file type names the type', () async {
      final report = await importer.importBytes(
        fileName: 'deck.pptx',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        subjectId: 'anything',
      );
      expect(report.ok, isFalse);
      expect(report.failure, contains('.pptx'));
    });

    test('a failed import stores nothing', () async {
      await importer.importBytes(
        fileName: 'scan.pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
        subjectId: 'chemistry',
      );
      expect(await storage.hasAnyResources(), isFalse);
    });

    test('removing a document takes all of its chunks', () async {
      final subjectId = (await subjects.create(name: 'Nutrition')).subjectId!;
      final report = await importer.importText(
        title: 'Food Groups',
        content: List.filled(60, 'Protein builds and repairs body tissue. ')
            .join(),
        subjectId: subjectId,
      );
      expect(report.chunkCount, greaterThan(1));

      final removed =
          await importer.removeDocument('Food Groups', subjectId: subjectId);
      expect(removed, report.chunkCount);
      expect(await storage.hasAnyResources(), isFalse);
    });
  });

  // ── The hardcoded syllabi are untouched ───────────────────────────────
  test('bundled subject ids are unchanged by any of this', () {
    expect(CustomSubjectService.reservedIds, containsAll(<String>[
      'mathematics',
      'physics',
      'biology',
      'chemistry',
      'programming',
      'agriculture',
      'history',
      'geography',
    ]));
    expect(CustomSubjectService.reservedIds, hasLength(16));
  });

  test('term markers keep their agreed values', () {
    expect(kAllTermsMarker, 0);
    expect(kTermMarkers, [0, 1, 2, 3]);
  });
}
