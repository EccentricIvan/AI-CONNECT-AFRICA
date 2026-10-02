import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/db/daos/topic_resource_dao.dart'
    show kPdfMarkerTopicKey;
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/features/learn/subject_notes.dart';

void main() {
  late OticDatabase db;

  setUp(() async {
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    final dao = db.topicResourceDao;
    Future<void> note(String subject, String? classUuid, {String? topic}) =>
        dao.insertChunk(
          subjectId: subject,
          topicKey: topic ?? 'cells',
          termMarker: 0,
          resourceTitle: 'Notes',
          contentChunk: 'Text for $subject',
          classGroupUuid: classUuid,
        );
    await note('own-biology', null);
    await note('own-biology', null);
    await note('class-a-physics', 'class-a');
    await note('class-b-history', 'class-b');
    // A note that is only a PDF still lists its subject.
    await note('class-a-maths', 'class-a', topic: kPdfMarkerTopicKey);
  });

  tearDown(() => db.close());

  test('a learner sees own notes plus their class, never another class', () async {
    final ids = await db.topicResourceDao.subjectIdsWithNotes(
      visibleClassUuid: 'class-a',
    );
    expect(
      ids.toSet(),
      {'own-biology', 'class-a-physics', 'class-a-maths'},
    );
    expect(ids.length, 3);
  });

  test('sections of an old upload show as one note, every part of it', () async {
    final dao = db.topicResourceDao;
    for (final s in ['Gases', 'Acids', 'Metals']) {
      // Rows from before document_title existed carry only the section title.
      await dao.insertChunk(
        subjectId: 'old-chemistry',
        topicKey: s.toLowerCase(),
        termMarker: 0,
        resourceTitle: 'Chemistry Chapter 2 — $s',
        contentChunk: 'Notes about $s in the chemical industry.',
      );
    }
    final rows = await dao.chunksForSubject(subjectId: 'old-chemistry', limit: null);
    final notes = await buildSubjectNotes(rows, const {}, (_) async => false);
    expect(notes.map((n) => n.title), ['Chemistry Chapter 2']);
    expect(notes.single.passages, hasLength(3));
  });

  test('a learner with no class sees only this device\'s own notes', () async {
    final ids = await db.topicResourceDao.subjectIdsWithNotes();
    expect(ids, ['own-biology']);
  });
}
