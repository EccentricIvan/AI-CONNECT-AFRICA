import 'dart:convert';

import '../../curriculum/curriculum_models.dart';
import '../../db/daos/topic_resource_dao.dart';
import '../../db/otic_database.dart';
import '../../features/learn/notes_quiz.dart';

/// Quiz questions written ahead of time from each page of a note's PDF.
///
/// Each question is one `topic_resources` row of the note (topic
/// [kQuizTopicKey]), so — like the PDF marker — it rides on everything the
/// note does: the teacher's signed digest covers it, it is shared,
/// unshared, relayed and deleted with the note, and a student's device
/// receives it on sync. Search and the notes text skip every `~` row.
class NoteQuizStore {
  NoteQuizStore(this._db);

  final OticDatabase _db;

  static final _pattern = RegExp(r'^\[QUIZ: page=(\d+)\] (.+)$', dotAll: true);

  /// The row text for [q], written from [page] of the PDF.
  static String format(QuizQuestion q, int page) =>
      '[QUIZ: page=$page] ${jsonEncode({
        'question': q.question,
        'options': q.options,
        'correctIndex': q.correct,
        'explanation': q.explanation,
      })}';

  /// The question and its page in [content], or null if it isn't one.
  static ({QuizQuestion question, int page})? parse(String content) {
    final m = _pattern.firstMatch(content.trim());
    if (m == null) return null;
    final q = NotesQuizGenerator.parse(m[2]!);
    if (q == null) return null;
    return (question: q, page: int.parse(m[1]!));
  }

  /// Every stored question of [subjectId] a learner in [classUuid] may take.
  Future<List<QuizQuestion>> questions(
    String subjectId, {
    String? classUuid,
  }) async {
    final rows = await _db.topicResourceDao.quizRows(
      subjectId: subjectId,
      visibleClassUuid: classUuid,
    );
    return [
      for (final r in rows)
        if (parse(r.contentChunk) case final p?) p.question,
    ];
  }
}
