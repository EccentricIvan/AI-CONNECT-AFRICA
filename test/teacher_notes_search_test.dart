import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/db/daos/topic_resource_dao.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/services/offline_rag_service.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';

class _RecordingEngine extends InferenceEngine {
  final prompts = <String>[];

  @override
  bool get isReady => true;

  @override
  String get backendLabel => 'test';

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    prompts.add(prompt);
    return 'ok';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('full-text search over teacher notes', () {
    late OticDatabase db;
    late OfflineStorageService storage;
    late OfflineRagService rag;

    setUp(() async {
      db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
      storage = OfflineStorageService(db);
      rag = OfflineRagService(storage);
      await storage.insertTopicResource(
        subjectId: 'Biology',
        topicKey: 'Photosynthesis',
        resourceTitle: 'Term 1 Biology Notes',
        content: 'Photosynthesis happens in the chloroplasts of green leaves. '
            'Chlorophyll absorbs sunlight to make glucose.',
      );
      await storage.insertTopicResource(
        subjectId: 'Chemistry',
        topicKey: 'Evaporation',
        resourceTitle: 'Water Cycle Handout',
        content: 'Evaporation turns liquid water into vapour when heated.',
      );
    });

    tearDown(() => db.close());

    test('finds notes from any subject without being told the subject',
        () async {
      final block = await rag.retrieveAcrossSubjects('what is chlorophyll');
      expect(block, contains('Term 1 Biology Notes'));
      expect(block, isNot(contains('Water Cycle Handout')));
    });

    test('matches inflected word forms (porter stemmer)', () async {
      final block = await rag.retrieveAcrossSubjects('why does water evaporate');
      expect(block, contains('Water Cycle Handout'));
    });

    test('matches derived forms the stemmer misses (prefix terms)', () async {
      final block =
          await rag.retrieveAcrossSubjects('photosynthesizing plants');
      expect(block, contains('Term 1 Biology Notes'));
    });

    test('a question with nothing searchable returns nothing', () async {
      expect(await rag.retrieveAcrossSubjects('why?'), isEmpty);
      expect(await rag.retrieveAcrossSubjects('quantum entanglement'), isEmpty);
    });

    test('FTS syntax in student text is searched literally, never parsed',
        () async {
      // Unquoted, `-`, `:` `*` `"` and NOT would be FTS5 operators — this
      // must neither throw nor change what is searched for.
      final block = await rag
          .retrieveAcrossSubjects('chlorophyll: NOT "sunlight" -leaves* (x');
      expect(block, contains('Term 1 Biology Notes'));
    });

    test('deleting a resource removes it from the index (trigger)', () async {
      await storage.deleteTopicResourceByTitle('Term 1 Biology Notes');
      expect(await rag.retrieveAcrossSubjects('chlorophyll'), isEmpty);
    });

    test('subject-scoped search stays inside the subject', () async {
      final hits = await storage.searchChunks(
        subjectId: 'chemistry',
        needle: 'chlorophyll water',
      );
      expect(hits.map((h) => h.subjectId).toSet(), {'chemistry'});
    });
  });

  test('buildFtsMatch quotes every term and ORs them', () {
    expect(buildFtsMatch('Acid: base!'), '"acid" OR "base"');
    expect(buildFtsMatch('photosynthesizing'),
        '"photosynthesizing" OR "photosynthes"*');
    expect(buildFtsMatch('a b ??'), isEmpty);
  });

  test('upgrading a v8 database indexes notes uploaded before the upgrade',
      () async {
    final dir = await Directory.systemTemp.createTemp('otic_fts_migration');
    final file = File('${dir.path}/otic.sqlite');
    try {
      // Build a current database, add material, then strip it back to the
      // v8 shape: no search index, no classes.
      var db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase(file)));
      await OfflineStorageService(db).insertTopicResource(
        subjectId: 'biology',
        topicKey: 'cells',
        resourceTitle: 'Old Cell Notes',
        content: 'Mitochondria release energy in the cell.',
      );
      for (final sql in [
        'DROP TRIGGER topic_resources_fts_ai',
        'DROP TRIGGER topic_resources_fts_ad',
        'DROP TRIGGER topic_resources_fts_au',
        'DROP TABLE topic_resources_fts',
        'ALTER TABLE students DROP COLUMN class_group_id',
        'DROP TABLE class_groups',
        'PRAGMA user_version = 8',
      ]) {
        await db.customStatement(sql);
      }
      await db.close();

      db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase(file)));
      final block = await OfflineRagService(OfflineStorageService(db))
          .retrieveAcrossSubjects('mitochondria');
      expect(block, contains('Old Cell Notes'));
      // And the classes half of v9 arrived too.
      expect(await db.classGroupDao.createClass(className: 'S2'), isPositive);
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('tutor prompt', () {
    test('folds teacher notes in, searching with the student words', () async {
      final engine = _RecordingEngine();
      final searched = <String>[];
      final tutor = TutorPipeline(
        engine: engine,
        teacherNotes: (text) async {
          searched.add(text);
          return 'Term 1 Notes:\nChlorophyll absorbs sunlight.';
        },
      );
      await tutor.respond(studentMessage: 'Explain chlorophyll to me');

      expect(searched.single, contains('chlorophyll'));
      final prompt = engine.prompts.single;
      expect(prompt, contains("TEACHER'S NOTES:"));
      expect(prompt, contains('Chlorophyll absorbs sunlight.'));
      expect(prompt, contains('CURRENT: Explain chlorophyll to me'));
    });

    test('long notes cannot push the question out of the prompt', () async {
      final engine = _RecordingEngine();
      final tutor = TutorPipeline(
        engine: engine,
        teacherNotes: (_) async => 'x' * 5000,
      );
      await tutor.respond(studentMessage: 'What is a cell');
      final prompt = engine.prompts.single;
      expect(prompt.length, lessThan(1600));
      expect(prompt, contains('CURRENT: What is a cell'));
    });

    test('a failing or slow lookup never blocks the reply', () async {
      final engine = _RecordingEngine();
      final tutor = TutorPipeline(
        engine: engine,
        teacherNotes: (_) => Future<String>.error(StateError('db gone')),
      );
      final reply = await tutor.respond(studentMessage: 'What is a cell');
      expect(reply.text, 'ok');
      expect(engine.prompts.single, isNot(contains("TEACHER'S NOTES:")));
    });
  });
}
