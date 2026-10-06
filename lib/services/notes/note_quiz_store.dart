import 'dart:convert';

import '../../curriculum/curriculum_models.dart';
import '../../db/daos/topic_resource_dao.dart';
import '../../db/otic_database.dart';
import '../../features/learn/notes_quiz.dart';

/// One stored question with the topic of the note it was written from.
class StoredQuizQuestion {
  const StoredQuizQuestion({
    required this.question,
    required this.topic,
    required this.documentTitle,
  });

  final QuizQuestion question;

  /// The note's section (heading) the question is about; the note's title
  /// for questions stored before topics existed.
  final String topic;
  final String documentTitle;
}

/// Quiz questions written ahead of time from each topic of a note.
///
/// Each question is one `topic_resources` row of the note (topic
/// [kQuizTopicKey]), so — like the PDF marker — it rides on everything the
/// note does: the teacher's signed digest covers it, it is shared,
/// unshared, relayed and deleted with the note, and a student's device
/// receives it on sync. Search and the notes text skip every `~` row.
///
/// The row is `[QUIZ: page=N] {json}`; the topic travels inside the JSON so
/// devices on the earlier per-page format still read the row.
class NoteQuizStore {
  NoteQuizStore(this._db);

  final OticDatabase _db;

  static final _pattern = RegExp(r'^\[QUIZ: page=(\d+)\] (.+)$', dotAll: true);

  /// The row text for [q], written from [page] of the PDF (0 when not
  /// known) under [topic].
  static String format(QuizQuestion q, int page, {String? topic}) =>
      '[QUIZ: page=$page] ${jsonEncode({
        'question': q.question,
        'options': q.options,
        'correctIndex': q.correct,
        'explanation': q.explanation,
        if (topic != null && topic.isNotEmpty) 'topic': topic,
      })}';

  /// The question, its page and topic in [content], or null if it isn't
  /// one.
  static ({QuizQuestion question, int page, String? topic})? parse(
    String content,
  ) {
    final m = _pattern.firstMatch(content.trim());
    if (m == null) return null;
    final q = NotesQuizGenerator.parse(m[2]!);
    if (q == null) return null;
    String? topic;
    try {
      final data = jsonDecode(m[2]!);
      if (data is Map && data['topic'] is String) {
        topic = (data['topic'] as String).trim();
        if (topic.isEmpty) topic = null;
      }
    } catch (_) {}
    return (question: q, page: int.parse(m[1]!), topic: topic);
  }

  static List<StoredQuizQuestion> fromRows(List<TopicResource> rows) => [
    for (final r in rows)
      if (parse(r.contentChunk) case final p?)
        StoredQuizQuestion(
          question: p.question,
          topic: p.topic ?? (r.documentTitle ?? r.resourceTitle),
          documentTitle: r.documentTitle ?? r.resourceTitle,
        ),
  ];

  /// Every stored question of [subjectId] a learner in [classUuid] may take.
  Future<List<StoredQuizQuestion>> questions(
    String subjectId, {
    String? classUuid,
  }) async => fromRows(
    await _db.topicResourceDao.quizRows(
      subjectId: subjectId,
      visibleClassUuid: classUuid,
    ),
  );

  /// [questions], live.
  Stream<List<StoredQuizQuestion>> watch(
    String subjectId, {
    String? classUuid,
  }) => _db.topicResourceDao
      .watchQuizRows(subjectId: subjectId, visibleClassUuid: classUuid)
      .map(fromRows);
}
