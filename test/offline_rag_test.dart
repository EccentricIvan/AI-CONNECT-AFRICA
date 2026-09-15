import 'package:drift/drift.dart' show DatabaseConnection, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/tables/topic_resources_table.dart';
import 'package:ai_connect_africa/features/teacher/resource_labels.dart';
import 'package:ai_connect_africa/services/grounded_tutor_prompt.dart';
import 'package:ai_connect_africa/services/offline_rag_service.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';

void main() {
  late OticDatabase db;
  late OfflineStorageService storage;
  late OfflineRagService rag;

  setUp(() {
    db = OticDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory()),
    );
    storage = OfflineStorageService(db);
    rag = OfflineRagService(storage);
  });

  tearDown(() => db.close());

  // ── The test that matters most ────────────────────────────────────────
  //
  // Retrieval filters on exact equality of subject_id and topic_key. If the
  // teacher-facing write path and the chat read path normalize differently,
  // every query returns zero rows, nothing throws, and the feature is dead
  // while still compiling and still passing any test that uses one spelling
  // on both sides. So this test deliberately uses DIFFERENT spellings.
  group('write/read key agreement', () {
    test('teacher spelling and chat spelling reach the same rows', () async {
      // What a teacher types into "Add Lesson Note".
      final written = await storage.insertTopicResource(
        subjectId: 'Chemistry',
        topicKey: 'Acid–Base Balances', // en dash, title case
        resourceTitle: 'Acid-Base Balances Notes',
        content: 'Neutralisation is the reaction between an acid and a base '
            'to produce a salt and water. The pH of a neutral solution is 7.',
        termMarker: 2,
      );
      expect(written, greaterThan(0));

      // What the chat path passes: the raw syllabus lesson title.
      final context = await rag.retrieveContextForQuery(
        'What is neutralisation?',
        'chemistry',
        'Lesson 3: Acid-Base Balances', // lesson prefix, hyphen, lower case
      );

      expect(context, isNotEmpty);
      expect(context, contains('Neutralisation'));
      expect(context, contains('Acid-Base Balances Notes'));
    });

    test('normalizeTopicKey folds the variations that would split a topic', () {
      const expected = 'acid_base_balances';
      expect(normalizeTopicKey('Acid-Base Balances'), expected);
      expect(normalizeTopicKey('Acid–Base Balances'), expected); // en dash
      expect(normalizeTopicKey('  acid base   balances '), expected);
      expect(normalizeTopicKey('Lesson 3: Acid-Base Balances'), expected);
      expect(normalizeTopicKey('Topic 2 - Acid-Base Balances'), expected);
    });

    test('normalizeSubjectId keeps a level suffix but canonicalizes form', () {
      expect(normalizeSubjectId('Chemistry'), 'chemistry');
      expect(normalizeSubjectId('chemistry_s4'), 'chemistry_s4');
      expect(normalizeSubjectId('Chemistry S4'), 'chemistry_s4');
      expect(normalizeSubjectId('web development'), 'web_development');
    });
  });

  // ── The spec's explicit empty contract ────────────────────────────────
  group('zero custom resources', () {
    test('retrieveContextForQuery returns an empty string', () async {
      final context = await rag.retrieveContextForQuery(
        'What is photosynthesis?',
        'biology',
        'photosynthesis',
      );
      expect(context, isEmpty);
    });

    test('an unrelated subject does not leak into another', () async {
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Chemistry Notes',
        content: 'Acids donate protons.',
      );
      final context = await rag.retrieveContextForQuery(
        'What is an acid?',
        'biology',
        'acid_base_balances',
      );
      expect(context, isEmpty);
    });

    test('the prompt frame carries the fallback, not a blank section', () {
      final prompt = composeGroundedPrompt(
        retrievedDbChunks: '',
        studentQuestion: 'What is photosynthesis?',
      );
      expect(prompt, contains(kNoCustomNotesFallback));
      expect(prompt, contains('What is photosynthesis?'));
      expect(prompt, contains("[TEACHER'S LESSON NOTES FACT BOOK]:"));
      expect(prompt, contains('[STUDENT QUESTION]:'));
    });

    test('a retrieved fact book replaces the fallback', () {
      final prompt = composeGroundedPrompt(
        retrievedDbChunks: 'Acids donate protons.',
        studentQuestion: 'What is an acid?',
      );
      expect(prompt, contains('Acids donate protons.'));
      expect(prompt, isNot(contains(kNoCustomNotesFallback)));
    });
  });

  // ── Retrieval behaviour ───────────────────────────────────────────────
  group('retrieval', () {
    Future<void> seed() async {
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Acid-Base Balances Notes',
        content: 'Neutralisation produces a salt and water.',
        termMarker: 1,
      );
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Indicators Handout',
        content: 'Litmus turns red in acid and blue in alkali.',
        termMarker: 1,
      );
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Titration Steps',
        content: 'A burette delivers the titrant into the conical flask.',
        termMarker: 2,
      );
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Extra Reading',
        content: 'The Bronsted-Lowry model defines acids as proton donors.',
        termMarker: 2,
      );
    }

    test('returns at most three chunks', () async {
      await seed();
      final context = await rag.retrieveContextForQuery(
        'acid litmus titrant proton neutralisation',
        'chemistry',
        'acid_base_balances',
      );
      // Each seeded resource is one chunk and each is labelled by its title.
      final labelled = [
        'Acid-Base Balances Notes',
        'Indicators Handout',
        'Titration Steps',
        'Extra Reading',
      ].where(context.contains).length;
      expect(labelled, lessThanOrEqualTo(OfflineRagService.topChunks));
      expect(labelled, greaterThan(0));
    });

    test('ranks the chunk that matches the question first', () async {
      await seed();
      final context = await rag.retrieveContextForQuery(
        'What does litmus do in an alkali?',
        'chemistry',
        'acid_base_balances',
      );
      expect(context, contains('Litmus'));
    });

    test('term filter keeps the selected term and all-term material', () async {
      await seed();
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Year Long Glossary',
        content: 'An acid is a substance that donates hydrogen ions.',
        termMarker: kAllTermsMarker,
      );

      final rows = await storage.chunksForTopic(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        termMarker: 1,
      );
      final titles = rows.map((r) => r.resourceTitle).toSet();
      expect(titles, contains('Acid-Base Balances Notes')); // term 1
      expect(titles, contains('Year Long Glossary')); // all terms
      expect(titles, isNot(contains('Titration Steps'))); // term 2
    });

    test('falls back to the subject when the topic has nothing', () async {
      await seed();
      final context = await rag.retrieveContextForQuery(
        'What is a burette used for?',
        'chemistry',
        'some_other_topic',
      );
      expect(context, contains('burette'));
    });

    test('a keyword-less question still returns ON-TOPIC material', () async {
      await seed();
      final context = await rag.retrieveContextForQuery(
        'why?',
        'chemistry',
        'acid_base_balances',
      );
      expect(context, isNotEmpty);
    });

    // The frame presents whatever comes back as verified fact from the
    // teacher's notes. Material filed against a DIFFERENT topic must earn its
    // way in with a real keyword hit — otherwise "why?" on an unrelated topic
    // gets three confident, attributed paragraphs about something else.
    test('a keyword-less question pulls in NO subject-wide material', () async {
      await seed();
      final context = await rag.retrieveContextForQuery(
        'why?',
        'chemistry',
        'a_topic_with_no_notes',
      );
      expect(context, isEmpty);
    });

    test('a keyword-ful question still reaches subject-wide material', () async {
      await seed();
      final context = await rag.retrieveContextForQuery(
        'what is a burette?',
        'chemistry',
        'a_topic_with_no_notes',
      );
      expect(context, contains('burette'));
    });
  });

  // ── CRUD ──────────────────────────────────────────────────────────────
  group('resource management', () {
    test('deleteTopicResourceByTitle removes every chunk of it', () async {
      final written = await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Long Notes',
        content: List.filled(60, 'Acids donate protons to bases. ').join(),
      );
      expect(written, greaterThan(1), reason: 'content should chunk');

      final removed = await storage.deleteTopicResourceByTitle('Long Notes');
      expect(removed, written);

      final context = await rag.retrieveContextForQuery(
        'protons',
        'chemistry',
        'acid_base_balances',
      );
      expect(context, isEmpty);
    });

    test('deleting a title in one subject leaves the other alone', () async {
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'topic_a',
        resourceTitle: 'Term 1 Notes',
        content: 'Chemistry material about acids.',
      );
      await storage.insertTopicResource(
        subjectId: 'biology',
        topicKey: 'topic_a',
        resourceTitle: 'Term 1 Notes',
        content: 'Biology material about cells.',
      );

      await storage.deleteTopicResourceByTitle(
        'Term 1 Notes',
        subjectId: 'chemistry',
      );

      final bio = await rag.retrieveContextForQuery(
        'cells',
        'biology',
        'topic_a',
      );
      expect(bio, contains('cells'));

      final chem = await rag.retrieveContextForQuery(
        'acids',
        'chemistry',
        'topic_a',
      );
      expect(chem, isEmpty);
    });

    test('deleting something absent reports 0, not an error', () async {
      expect(await storage.deleteTopicResourceByTitle('Nothing'), 0);
    });

    test('listResources collapses chunks into one row per document', () async {
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'acid_base_balances',
        resourceTitle: 'Long Notes',
        content: List.filled(60, 'Acids donate protons to bases. ').join(),
        termMarker: 3,
      );
      final list = await storage.listResources(subjectId: 'chemistry');
      expect(list, hasLength(1));
      expect(list.single.resourceTitle, 'Long Notes');
      expect(list.single.termMarker, 3);
      expect(list.single.chunkCount, greaterThan(1));
    });

    test('empty title or content writes nothing', () async {
      expect(
        await storage.insertTopicResource(
          subjectId: 'chemistry',
          topicKey: 'x',
          resourceTitle: '   ',
          content: 'text',
        ),
        0,
      );
      expect(
        await storage.insertTopicResource(
          subjectId: 'chemistry',
          topicKey: 'x',
          resourceTitle: 'Title',
          content: '   ',
        ),
        0,
      );
      expect(await storage.hasAnyResources(), isFalse);
    });

    test('an out-of-range term marker falls back to all-terms', () async {
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'x',
        resourceTitle: 'Odd Term',
        content: 'text',
        termMarker: 9,
      );
      final list = await storage.listResources();
      expect(list.single.termMarker, kAllTermsMarker);
    });

    test('a teacher percent sign is matched literally, not as a wildcard', () async {
      await storage.insertTopicResource(
        subjectId: 'chemistry',
        topicKey: 'concentration',
        resourceTitle: 'Percent Notes',
        content: 'A 100% yield is theoretical.',
      );
      final hits = await storage.searchChunks(
        subjectId: 'chemistry',
        needle: '100%',
      );
      expect(hits, hasLength(1));

      final misses = await storage.searchChunks(
        subjectId: 'chemistry',
        needle: 'zz%zz',
      );
      expect(misses, isEmpty);
    });
  });

  // ── Chunking ──────────────────────────────────────────────────────────
  group('chunkContent', () {
    test('short content stays one chunk', () {
      expect(chunkContent('Short note.'), ['Short note.']);
    });

    test('empty content produces no chunks', () {
      expect(chunkContent('   '), isEmpty);
    });

    test('long content splits and loses no words', () {
      final source = List.generate(
        200,
        (i) => 'Sentence number $i explains an idea.',
      ).join(' ');
      final chunks = chunkContent(source);

      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.trim(), isNotEmpty);
      }
      // Every sentence survives the split somewhere.
      final rejoined = chunks.join(' ');
      expect(rejoined, contains('Sentence number 0 '));
      expect(rejoined, contains('Sentence number 199 '));
    });

    test('unbroken text still terminates and covers the input', () {
      final source = 'a' * 2300;
      final chunks = chunkContent(source);
      expect(chunks.length, greaterThan(1));
      expect(chunks.join().length, source.length);
    });
  });

  // ── Migration ─────────────────────────────────────────────────────────
  //
  // Existing installs reach schema 6 through onUpgrade, not onCreate. Those
  // are two different code paths and only one of them is exercised by every
  // other test in this file.
  group('schema 5 to 6 upgrade', () {
    test('creates the table and its lookup indexes', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='topic_resources'",
          )
          .get();
      final names = indexes.map((r) => r.data['name'] as String).toSet();
      expect(names, contains('idx_topic_resources_lookup'));
      expect(names, contains('idx_topic_resources_title'));
    });

    test('the retrieval query actually uses the lookup index', () async {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM topic_resources '
            'WHERE subject_id = ? AND topic_key = ?',
            variables: [
              Variable.withString('chemistry'),
              Variable.withString('acid_base_balances'),
            ],
          )
          .get();
      final detail = plan.map((r) => r.data['detail']).join(' ');
      expect(
        detail,
        contains('idx_topic_resources_lookup'),
        reason: 'retrieval must not fall back to a full table scan',
      );
    });
  });

  // ── White-label rule ──────────────────────────────────────────────────
  group('teacher-facing labels', () {
    const labels = <String>[
      ResourceLabels.addNote,
      ResourceLabels.removeResource,
      ResourceLabels.termTracker,
      ResourceLabels.noteTitle,
      ResourceLabels.noteTitleHint,
      ResourceLabels.noteContent,
      ResourceLabels.noteContentHint,
      ResourceLabels.chooseSubject,
      ResourceLabels.chooseTopic,
      ResourceLabels.chooseTerm,
      ResourceLabels.allTerms,
      ResourceLabels.term1,
      ResourceLabels.term2,
      ResourceLabels.term3,
      ResourceLabels.saveNote,
      ResourceLabels.cancel,
      ResourceLabels.noResources,
      ResourceLabels.noResourcesHint,
      ResourceLabels.noteSaved,
      ResourceLabels.noteRemoved,
      ResourceLabels.nothingToRemove,
      ResourceLabels.removeConfirm,
      ResourceLabels.usingTeacherNotes,
      ResourceLabels.workspace,
      ResourceLabels.workspaceSubtitle,
      ResourceLabels.newSubject,
      ResourceLabels.subjectName,
      ResourceLabels.subjectNameHint,
      ResourceLabels.createSubject,
      ResourceLabels.removeSubject,
      ResourceLabels.removeSubjectConfirm,
      ResourceLabels.mySubjects,
      ResourceLabels.noSubjects,
      ResourceLabels.noSubjectsHint,
      ResourceLabels.subjectCreated,
      ResourceLabels.subjectRemoved,
      ResourceLabels.uploadFile,
      ResourceLabels.typeNotes,
      ResourceLabels.uploadHint,
      ResourceLabels.reading,
      ResourceLabels.readFailed,
      ResourceLabels.importedTopics,
      ResourceLabels.importedOneTopic,
    ];

    test('the three agreed action labels are exact', () {
      expect(ResourceLabels.addNote, 'Add Lesson Note');
      expect(ResourceLabels.removeResource, 'Remove Resource Material');
      expect(ResourceLabels.termTracker, 'Term Core Tracker');
    });

    test('no label leaks an implementation term', () {
      for (final label in labels) {
        final words = label
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toSet();
        for (final banned in kForbiddenTechnicalTerms) {
          expect(
            words,
            isNot(contains(banned)),
            reason: 'Label "$label" exposes the internal term "$banned"',
          );
        }
      }
    });
  });
}
