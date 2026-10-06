import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';

/// A learner's results on one topic: the latest round and the best one.
class TopicQuizScore {
  const TopicQuizScore({
    required this.subjectId,
    required this.topic,
    required this.lastCorrect,
    required this.lastTotal,
    required this.bestPercent,
    required this.rounds,
    required this.lastAt,
  });

  final String subjectId;
  final String topic;
  final int lastCorrect;
  final int lastTotal;
  final int bestPercent;
  final int rounds;
  final DateTime lastAt;
}

/// Quiz results per learner and topic (`quiz_results`).
class QuizScores {
  QuizScores(this._db);

  final OticDatabase _db;

  /// Records one finished round: [byTopic] maps each topic in it to
  /// (correct, total).
  Future<void> record({
    required int studentId,
    required String subjectId,
    required Map<String, (int, int)> byTopic,
    DateTime? at,
  }) async {
    final stamp = (at ?? DateTime.now()).toUtc().toIso8601String();
    await _db.batch(
      (b) => b.insertAll(_db.quizResults, [
        for (final e in byTopic.entries)
          if (e.value.$2 > 0)
            QuizResultsCompanion.insert(
              studentId: studentId,
              subjectId: subjectId,
              topic: e.key,
              correct: e.value.$1,
              total: e.value.$2,
              takenAt: stamp,
            ),
      ]),
    );
  }

  /// [studentId]'s scores per subject and topic, most recent first.
  Stream<List<TopicQuizScore>> watch(int studentId) =>
      (_db.select(_db.quizResults)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch()
          .map(summarize);

  static List<TopicQuizScore> summarize(List<QuizResult> rows) {
    final byKey = <(String, String), List<QuizResult>>{};
    for (final r in rows) {
      (byKey[(r.subjectId, r.topic)] ??= []).add(r);
    }
    final out = [
      for (final e in byKey.entries)
        TopicQuizScore(
          subjectId: e.key.$1,
          topic: e.key.$2,
          lastCorrect: e.value.last.correct,
          lastTotal: e.value.last.total,
          bestPercent: e.value
              .map((r) => (r.correct * 100 / r.total).round())
              .reduce((a, b) => a > b ? a : b),
          rounds: e.value.length,
          lastAt: DateTime.tryParse(e.value.last.takenAt) ?? DateTime(0),
        ),
    ]..sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return out;
  }
}

final quizScoresProvider = Provider<QuizScores>(
  (ref) => QuizScores(ref.watch(dbProvider)),
);

/// One learner's quiz scores, live.
final learnerQuizScoresProvider = StreamProvider.autoDispose
    .family<List<TopicQuizScore>, int>(
      (ref, studentId) => ref.watch(quizScoresProvider).watch(studentId),
    );
