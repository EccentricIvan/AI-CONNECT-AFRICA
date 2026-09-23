import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/tutor/conversation_memory.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/memory/session_recall.dart';
import 'package:ai_connect_africa/memory/session_recall_store.dart';

void main() {
  late OticDatabase db;
  late int studentId;

  setUp(() async {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    studentId = await db.into(db.students).insert(
          StudentsCompanion.insert(name: 'Amina'),
        );
  });

  tearDown(() => db.close());

  // ── The test that matters most ────────────────────────────────────────
  //
  // The bug this whole change exists to fix is that every assistant turn
  // INSERTED a new row, so one conversation showed up in the sidebar a dozen
  // times. The index must key on the session id and UPDATE on later turns.
  // Nothing throws either way — the only symptom is a duplicated list — so
  // this asserts the row count directly.
  group('chat session index', () {
    test('a second turn updates the row instead of inserting another',
        () async {
      final dao = db.chatSessionDao;
      const id = 's_test_one';

      await dao.upsertSession(
        id: id,
        studentId: studentId,
        title: 'how do I factor x^2+5x+6',
        topic: 'mathematics',
        preview: 'Find two numbers that multiply to 6',
        stage: 'answer',
        turnCount: 1,
        updatedAt: DateTime(2026, 9, 21, 10),
      );
      await dao.upsertSession(
        id: id,
        studentId: studentId,
        title: 'how do I factor x^2+5x+6',
        topic: 'mathematics',
        preview: 'Now try x^2+7x+12 yourself',
        stage: 'practice',
        turnCount: 2,
        updatedAt: DateTime(2026, 9, 21, 10, 5),
      );

      final rows = await dao.recentSessions(studentId);
      expect(rows, hasLength(1), reason: 'one chat must be one row');
      expect(rows.single.turnCount, 2);
      expect(rows.single.stage, 'practice');
      expect(rows.single.preview, 'Now try x^2+7x+12 yourself');
    });

    test('a chat keeps the time it started but sorts by last activity',
        () async {
      final dao = db.chatSessionDao;
      await dao.upsertSession(
        id: 's_old',
        studentId: studentId,
        title: 'photosynthesis',
        topic: 'biology',
        preview: 'Plants convert light',
        stage: 'answer',
        turnCount: 1,
        updatedAt: DateTime(2026, 9, 20, 9),
      );
      await dao.upsertSession(
        id: 's_new',
        studentId: studentId,
        title: 'newtons laws',
        topic: 'physics',
        preview: 'An object at rest',
        stage: 'answer',
        turnCount: 1,
        updatedAt: DateTime(2026, 9, 21, 9),
      );
      // Revisiting the older chat must float it to the top without
      // rewriting when it began.
      await dao.upsertSession(
        id: 's_old',
        studentId: studentId,
        title: 'photosynthesis',
        topic: 'biology',
        preview: 'Chlorophyll absorbs red and blue',
        stage: 'clarify',
        turnCount: 2,
        updatedAt: DateTime(2026, 9, 21, 11),
      );

      final rows = await dao.recentSessions(studentId);
      expect(rows.map((r) => r.id), ['s_old', 's_new']);
      expect(rows.first.createdAt, DateTime(2026, 9, 20, 9),
          reason: 'createdAt must survive later turns');
    });

    test('sessions are scoped to their student', () async {
      final other = await db.into(db.students).insert(
            StudentsCompanion.insert(name: 'Joseph'),
          );
      final dao = db.chatSessionDao;
      await dao.upsertSession(
        id: 's_a',
        studentId: studentId,
        title: 'algebra',
        topic: 'mathematics',
        preview: '',
        stage: 'answer',
        turnCount: 1,
      );
      await dao.upsertSession(
        id: 's_b',
        studentId: other,
        title: 'chemistry',
        topic: 'chemistry',
        preview: '',
        stage: 'answer',
        turnCount: 1,
      );

      expect(await dao.recentSessions(studentId), hasLength(1));
      expect(await dao.recentSessions(other), hasLength(1));
      expect((await dao.allSessionIds()), {'s_a', 's_b'});
    });

    // Nothing in this app turns on `PRAGMA foreign_keys`, so the cascade
    // declared on this table (and on every other child table here) is never
    // enforced by SQLite. Removing a student therefore has to clear their
    // chats explicitly, and this pins that contract.
    test('removing a student clears their chats and reports the file ids',
        () async {
      final dao = db.chatSessionDao;
      final other = await db.into(db.students).insert(
            StudentsCompanion.insert(name: 'Joseph'),
          );
      for (final id in ['s_gone_a', 's_gone_b']) {
        await dao.upsertSession(
          id: id,
          studentId: studentId,
          title: 'ratios',
          topic: 'mathematics',
          preview: '',
          stage: 'answer',
          turnCount: 1,
        );
      }
      await dao.upsertSession(
        id: 's_kept',
        studentId: other,
        title: 'atoms',
        topic: 'chemistry',
        preview: '',
        stage: 'answer',
        turnCount: 1,
      );

      final removed = await dao.deleteForStudent(studentId);
      expect(removed, {'s_gone_a', 's_gone_b'});
      expect(await dao.recentSessions(studentId), isEmpty);
      expect(await dao.recentSessions(other), hasLength(1),
          reason: 'another student must be untouched');
    });

    test('deleteSession removes just the one chat', () async {
      final dao = db.chatSessionDao;
      for (final id in ['s_one', 's_two']) {
        await dao.upsertSession(
          id: id,
          studentId: studentId,
          title: id,
          topic: '',
          preview: '',
          stage: 'answer',
          turnCount: 1,
        );
      }
      await dao.deleteSession('s_one');
      final rows = await dao.recentSessions(studentId);
      expect(rows.map((r) => r.id), ['s_two']);
      expect(await dao.findSession('s_one'), isNull);
    });
  });

  // ── File store ────────────────────────────────────────────────────────
  group('recall file store', () {
    late Directory tmp;
    late SessionRecallStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('otic_recall_test');
      store = SessionRecallStore(directory: tmp);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('a saved session round-trips off disk', () async {
      final memory = ConversationMemory()
        ..remember(
          student: 'how do I factor x^2+5x+6',
          tutor: 'Look for two numbers that multiply to 6 and add to 5.',
          verified: ['factoring finds the roots'],
        );

      final recall = SessionRecall(
        id: SessionRecallStore.newSessionId(),
        studentId: studentId,
        title: 'how do I factor x^2+5x+6',
        topic: 'mathematics',
        stage: 'practice',
        createdAt: DateTime(2026, 9, 21, 10),
        updatedAt: DateTime(2026, 9, 21, 10, 5),
      ).withExchange(
        question: 'how do I factor x^2+5x+6',
        answer: 'Look for two numbers that multiply to 6 and add to 5.',
        stage: 'practice',
        memory: memory.toJson(),
      );

      expect(await store.save(recall), isTrue);
      final back = await store.load(recall.id);

      expect(back, isNotNull);
      expect(back!.title, recall.title);
      expect(back.topic, 'mathematics');
      expect(back.stage, 'practice');
      expect(back.exchanges, hasLength(1));
      expect(back.exchanges.single.question, 'how do I factor x^2+5x+6');
      expect(back.createdAt, DateTime(2026, 9, 21, 10));

      // And the tutor's own memory survives, which is what lets a reopened
      // chat resume instead of cold-starting.
      final restored = ConversationMemory()..restoreFrom(back.memory);
      expect(restored.exchangeCount, 1);
      expect(restored.anchorQuestion, contains('factor'));
      expect(restored.established, isNotEmpty);
    });

    test('saving twice replaces rather than appends', () async {
      final base = SessionRecall(
        id: 's_replace',
        studentId: studentId,
        title: 'first',
        topic: '',
        stage: 'answer',
        createdAt: DateTime(2026, 9, 21),
        updatedAt: DateTime(2026, 9, 21),
      );
      await store.save(base);
      await store.save(base.copyWith(title: 'second'));

      expect((await store.load('s_replace'))!.title, 'second');
      final files = tmp.listSync().whereType<File>().toList();
      expect(files, hasLength(1), reason: 'no .tmp left behind');
    });

    test('a damaged file reads as missing instead of throwing', () async {
      await File('${tmp.path}/s_broken.json').writeAsString('{not json');
      expect(await store.load('s_broken'), isNull);
    });

    test('a file from a future format version is refused', () async {
      await File('${tmp.path}/s_future.json')
          .writeAsString(jsonEncode({'v': 99, 'id': 's_future'}));
      expect(await store.load('s_future'), isNull);
    });

    test('an id that could escape the folder is refused', () async {
      expect(await store.load('../../secrets'), isNull);
      expect(
        await store.save(SessionRecall(
          id: '../escape',
          studentId: studentId,
          title: 'x',
          topic: '',
          stage: 'answer',
          createdAt: DateTime(2026, 9, 21),
          updatedAt: DateTime(2026, 9, 21),
        )),
        isFalse,
      );
    });

    test('pruning removes files the index no longer knows about', () async {
      for (final id in ['s_keep', 's_orphan']) {
        await store.save(SessionRecall(
          id: id,
          studentId: studentId,
          title: id,
          topic: '',
          stage: 'answer',
          createdAt: DateTime(2026, 9, 21),
          updatedAt: DateTime(2026, 9, 21),
        ));
      }
      expect(await store.pruneExcept({'s_keep'}), 1);
      expect(await store.load('s_keep'), isNotNull);
      expect(await store.load('s_orphan'), isNull);
    });
  });

  // ── Compression guarantees ────────────────────────────────────────────
  //
  // CLAUDE.md's memory rule is "compressed summaries only — never full
  // conversation logs". These assert the file physically cannot become a
  // transcript, however long the chat runs.
  group('stays a compressed recall', () {
    test('long messages are clipped, not stored whole', () {
      final essay = List.filled(400, 'word').join(' ');
      final recall = SessionRecall(
        id: 's_long',
        studentId: 1,
        title: SessionRecall.titleFrom(essay),
        topic: '',
        stage: 'answer',
        createdAt: DateTime(2026, 9, 21),
        updatedAt: DateTime(2026, 9, 21),
      ).withExchange(
        question: essay,
        answer: essay,
        stage: 'answer',
        memory: const {},
      );

      expect(recall.title.length, lessThanOrEqualTo(SessionRecall.titleChars + 1));
      final e = recall.exchanges.single;
      expect(e.question.length, lessThanOrEqualTo(SessionRecall.clipChars + 1));
      expect(e.answer.length, lessThanOrEqualTo(SessionRecall.clipChars + 1));
      expect(e.question, isNot(contains(essay)));
    });

    test('a very long chat stops growing and stays a small file', () {
      var recall = SessionRecall(
        id: 's_many',
        studentId: 1,
        title: 'marathon',
        topic: 'mathematics',
        stage: 'answer',
        createdAt: DateTime(2026, 9, 21),
        updatedAt: DateTime(2026, 9, 21),
      );
      for (var i = 0; i < SessionRecall.maxExchanges * 3; i++) {
        recall = recall.withExchange(
          question: 'question number $i about algebra and fractions',
          answer: 'answer number $i explaining the steps in some detail',
          stage: 'answer',
          memory: const {},
        );
      }

      expect(recall.exchanges, hasLength(SessionRecall.maxExchanges));
      // Oldest dropped, newest kept.
      expect(recall.exchanges.last.question, contains('number 119'));
      expect(recall.exchanges.first.question, contains('number 80'));
      // "Small tiny retrievable files" — assert the bound in bytes.
      expect(utf8.encode(recall.encode()).length, lessThan(32 * 1024));
    });

    test('an empty first message still yields a usable title', () {
      expect(SessionRecall.titleFrom('   '), 'New chat');
    });
  });

  // ── Memory snapshot ───────────────────────────────────────────────────
  group('conversation memory snapshot', () {
    test('restoreFrom rebuilds turns, facts, digest and anchor', () {
      final original = ConversationMemory();
      for (var i = 0; i < 5; i++) {
        original.remember(
          student: 'student question $i about photosynthesis',
          tutor: 'tutor answer $i explaining chlorophyll',
          verified: ['fact $i'],
        );
      }

      final copy = ConversationMemory()..restoreFrom(original.toJson());

      expect(copy.turns.length, original.turns.length);
      expect(copy.exchangeCount, original.exchangeCount);
      expect(copy.established, original.established);
      expect(copy.lessonDigest, original.lessonDigest);
      expect(copy.anchorQuestion, original.anchorQuestion);
      expect(copy.promptBlock(), original.promptBlock());
    });

    test('a malformed snapshot degrades instead of throwing', () {
      final m = ConversationMemory()
        ..restoreFrom({
          'turns': [
            {'role': 'tutor', 'text': 'orphan reply with no question'},
            'not a map',
            {'role': 'bogus', 'text': 'x'},
          ],
          'facts': ['ok fact', 42],
          'digest': 123,
        });

      // A leading tutor line is dropped so turns stay Student/Tutor pairs.
      expect(m.turns.length.isEven, isTrue);
      expect(m.established, ['ok fact']);
      expect(m.lessonDigest, isNull);
      expect(m.promptBlock(), isNotNull);
    });

    test('restoring twice does not accumulate', () {
      final original = ConversationMemory()
        ..remember(student: 'q', tutor: 'a', verified: ['f']);
      final copy = ConversationMemory()
        ..restoreFrom(original.toJson())
        ..restoreFrom(original.toJson());
      expect(copy.exchangeCount, 1);
      expect(copy.established, ['f']);
    });
  });
}
