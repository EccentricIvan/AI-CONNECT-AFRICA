import 'dart:math';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/db/daos/topic_resource_dao.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/learn/notes_quiz.dart';
import 'package:ai_connect_africa/features/learn/subject_notes.dart';
import 'package:ai_connect_africa/services/notes/note_pdf_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedEngine extends InferenceEngine {
  _ScriptedEngine(this.reply);

  final String reply;
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
    return reply;
  }

  @override
  Future<void> dispose() async {}
}

TopicResource _row(
  int id,
  String doc,
  String content, {
  String topic = 'cells',
}) => TopicResource(
  id: id,
  subjectId: 's2_biology',
  topicKey: topic,
  termMarker: 0,
  resourceTitle: doc,
  contentChunk: content,
  createdAt: '2026-10-01T00:00:00Z',
  documentTitle: doc,
);

void main() {
  final longA =
      'Cells are the basic unit of life. Every living thing is made of one '
      'or more cells, and new cells come only from existing cells by division.';
  final longB =
      'Photosynthesis takes place in the chloroplasts. Plants use light, water '
      'and carbon dioxide to make glucose, and release oxygen as a by-product.';

  group('notes for a subject', () {
    test('are one note per document, in upload order, without the PDF record',
        () async {
      const sha =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final pdf = NotePdf(
        sha256: sha,
        pages: 2,
        bytes: 10,
        subjectId: 's2_biology',
        documentTitle: 'Cells',
      );
      final notes = await buildSubjectNotes(
        [
          _row(3, 'Plants', longB),
          _row(1, 'Cells', longA),
          _row(
            2,
            'Cells',
            NotePdf.markerText(sha, 2, 10),
            topic: kPdfMarkerTopicKey,
          ),
        ],
        {'Cells': pdf},
        (s) async => s == sha,
      );
      expect([for (final n in notes) n.title], ['Cells', 'Plants']);
      expect(notes.first.pdf, same(pdf));
      expect(notes.first.pdfOnDevice, isTrue);
      expect(notes.first.text, isNot(contains('[PDF:')));
      expect(notes.last.pdf, isNull);
    });

    test('show diagram markers as a short page pointer', () {
      final text = readableNoteText(
        'The heart pumps blood.\n\n'
        '[DIAGRAM: Figure 3.2 The heart | page 14 of the PDF "Biology"]',
      );
      expect(text, contains('[Figure 3.2 The heart — page 14]'));
      expect(text, isNot(contains('[DIAGRAM:')));
    });
  });

  group('quiz from the notes', () {
    test('takes passages from every document before repeating one', () {
      final notes = [
        SubjectNote(title: 'Cells', passages: [longA, longA, longA]),
        SubjectNote(title: 'Plants', passages: [longB]),
        const SubjectNote(title: 'Short', passages: ['Too short to ask about.']),
      ];
      final picked = NotesQuizGenerator.pickPassages(
        notes,
        count: 3,
        random: Random(1),
      );
      expect(picked, hasLength(3));
      expect(picked, contains(longB));
      expect(picked, isNot(contains('Too short to ask about.')));
    });

    test('asks the model about the passage and keeps a valid question',
        () async {
      final engine = _ScriptedEngine(
        'Sure! {"question": "Where does photosynthesis happen?", '
        '"options": ["Chloroplasts", "Nucleus", "Roots", "Cell wall"], '
        '"correctIndex": 0, "explanation": "In the chloroplasts."}',
      );
      final q = await NotesQuizGenerator(
        engine,
      ).fromPassage(longB, subject: 'Biology');
      expect(q?.question, 'Where does photosynthesis happen?');
      expect(q?.correct, 0);
      expect(engine.prompts.single, contains('chloroplasts'));
    });

    test('drops malformed questions', () {
      for (final raw in [
        'no json here',
        '{"question": "Q?", "options": ["a", "b", "c"], "correctIndex": 0}',
        '{"question": "Q?", "options": ["a", "a", "b", "c"], "correctIndex": 0}',
        '{"question": "Q?", "options": ["a", "b", "c", "d"], "correctIndex": 7}',
        '{"question": "", "options": ["a", "b", "c", "d"], "correctIndex": 1}',
      ]) {
        expect(NotesQuizGenerator.parse(raw), isNull, reason: raw);
      }
    });
  });
}
