import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/curriculum/curriculum_models.dart';
import 'package:ai_connect_africa/db/daos/topic_resource_dao.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/learn/notes_quiz.dart';
import 'package:ai_connect_africa/features/learn/subject_notes.dart';
import 'package:ai_connect_africa/services/custom_subject_service.dart';
import 'package:ai_connect_africa/services/notes/note_quiz_store.dart';
import 'package:ai_connect_africa/services/resource_import_service.dart';
import 'package:ai_connect_africa/services/resource_text_extractor.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Engine extends InferenceEngine {
  _Engine(this.reply);
  final String reply;

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'Fake';
  @override
  Future<void> loadModel(String modelPath) async {}
  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async => reply;
  @override
  Future<void> dispose() async {}
}

const _question = QuizQuestion(
  question: 'What gas do plants take in?',
  options: ['Oxygen', 'Carbon dioxide', 'Nitrogen', 'Helium'],
  correct: 1,
  explanation: 'Plants take in carbon dioxide for photosynthesis.',
);

void main() {
  test('a stored question reads back with its page', () {
    final row = NoteQuizStore.format(_question, 14);
    final back = NoteQuizStore.parse(row)!;
    expect(back.page, 14);
    expect(back.question.question, _question.question);
    expect(back.question.options, _question.options);
    expect(back.question.correct, 1);
    expect(NoteQuizStore.parse('Plants take in carbon dioxide.'), isNull);
  });

  group('question rows', () {
    late OticDatabase db;

    setUp(() async {
      db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
      final dao = db.topicResourceDao;
      await dao.insertChunks([
        TopicResourcesCompanion.insert(
          subjectId: 'biology',
          topicKey: 'photosynthesis',
          resourceTitle: 'Plants',
          contentChunk: 'Plants take in carbon dioxide and give out oxygen.',
          createdAt: '2026-10-01T00:00:00Z',
          documentTitle: const Value('Plants'),
        ),
      ]);
      await dao.insertQuizRow(
        subjectId: 'biology',
        documentTitle: 'Plants',
        content: NoteQuizStore.format(_question, 1),
        termMarker: 0,
      );
      // Another class's question, received on this shared device.
      await dao.insertChunk(
        subjectId: 'biology',
        topicKey: kQuizTopicKey,
        termMarker: 0,
        resourceTitle: 'Other',
        contentChunk: NoteQuizStore.format(_question, 2),
        classGroupUuid: 'class-b',
      );
    });

    tearDown(() => db.close());

    test('never reach the tutor search or the notes text', () async {
      final dao = db.topicResourceDao;
      final hits = await dao.searchAllChunks(needle: 'carbon dioxide plants');
      expect(hits.map((r) => r.topicKey), everyElement(isNot(kQuizTopicKey)));
      expect(hits, isNotEmpty);

      final chunks = await dao.chunksForSubject(subjectId: 'biology', limit: null);
      expect(chunks.map((r) => r.topicKey), ['photosynthesis']);

      final notes = await buildSubjectNotes(
        await (db.select(db.topicResources)).get(),
        const {},
        (_) async => false,
      );
      expect(notes.expand((n) => n.passages).join(), isNot(contains('QUIZ')));
    });

    test('a learner gets own and class questions, never another class', () async {
      final store = NoteQuizStore(db);
      expect(await store.questions('biology'), hasLength(1));
      expect(await store.questions('biology', classUuid: 'class-b'), hasLength(2));
      expect(await store.questions('biology', classUuid: 'class-a'), hasLength(1));
    });

    test('a new upload of the note drops its old questions', () async {
      await db.topicResourceDao.deleteQuizRows(
        subjectId: 'biology',
        documentTitle: 'Plants',
      );
      expect(await NoteQuizStore(db).questions('biology'), isEmpty);
    });
  });

  test('an engine failure is reported, so the page is retried not skipped', () async {
    final failed = await NotesQuizGenerator(
      _Engine('I hit a brief snag finishing that answer. Please ask again.'),
    ).tryPassage('Plants take in carbon dioxide.', subject: 'Biology');
    expect(failed.engineFailed, isTrue);
    expect(failed.question, isNull);

    final ok = await NotesQuizGenerator(
      _Engine(
        '{"question": "What gas do plants take in?", "options": ["Oxygen", '
        '"Carbon dioxide", "Nitrogen", "Helium"], "correctIndex": 1, '
        '"explanation": "Carbon dioxide."}',
      ),
    ).tryPassage('Plants take in carbon dioxide.', subject: 'Biology');
    expect(ok.engineFailed, isFalse);
    expect(ok.question?.correct, 1);
  });

  group('unreadable PDF text', () {
    const garbage = '\u0001~\u0002P\u0003\u0004\u0005\u0006W\u0007\u0008îK\u000e\u000f~\u0010P\u0011';

    test('lines of unmapped-font symbols are dropped', () {
      final text = normalizeExtractedText(
        'Industrial processes\n$garbage\nThe Haber process makes ammonia.',
      );
      expect(text, 'Industrial processes\nThe Haber process makes ammonia.');
    });

    test('never become headings or lesson titles', () {
      expect(looksLikeHeading('~PWîK~P'), isFalse);
      expect(looksLikeHeading('INDUSTRIAL PROCESSES'), isTrue);
      expect(looksLikeHeading('Chapter 2 – Industrial processes'), isTrue);
      expect(
        cleanLessonTitle('Chemistry Chapter 2 — $garbage'),
        'Chemistry Chapter 2',
      );
      expect(
        cleanLessonTitle('Chemistry Chapter 2 — ~=îK~P^î&~'),
        'Chemistry Chapter 2',
      );
      expect(
        cleanLessonTitle('Chemistry Chapter 2 — The Contact Process'),
        'Chemistry Chapter 2 — The Contact Process',
      );
    });
  });
}
