import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../curriculum/curriculum_models.dart';
import '../../services/custom_subject_service.dart';
import 'subject_notes.dart';

/// Multiple-choice questions written from the teacher's own notes — one
/// passage per question, so each question can be answered from what the
/// class was given, not from whatever the model happens to know.
class NotesQuizGenerator {
  NotesQuizGenerator(this._engine);

  final InferenceEngine _engine;

  /// Passages long enough to ask about, spread across the documents.
  static List<String> pickPassages(
    List<SubjectNote> notes, {
    int count = 5,
    math.Random? random,
  }) {
    final rnd = random ?? math.Random();
    final byDoc = [
      for (final n in notes)
        [
          for (final p in n.passages)
            if (p.length >= 120) p,
        ]..shuffle(rnd),
    ]..removeWhere((l) => l.isEmpty);
    final out = <String>[];
    // Round-robin, so one long document doesn't take every question.
    while (out.length < count && byDoc.any((l) => l.isNotEmpty)) {
      for (final l in byDoc) {
        if (l.isNotEmpty && out.length < count) out.add(l.removeLast());
      }
    }
    return out;
  }

  Future<QuizQuestion?> fromPassage(
    String passage, {
    required String subject,
  }) async {
    final clipped = passage.length > 900 ? passage.substring(0, 900) : passage;
    final prompt =
        '''You are a teacher writing a quiz for students of $subject.
Read the passage from the class notes, then write ONE multiple-choice question that can be answered using only this passage.

Passage:
"""
$clipped
"""

Respond ONLY with this JSON (no markdown, no explanation):
{"question": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0, "explanation": "One sentence, quoting or paraphrasing the passage."}

Rules:
- Exactly 4 different options; only one is correct according to the passage.
- correctIndex is 0-3.
- Do not mention "the passage" in the question.''';
    try {
      final raw = await _engine.generate(
        prompt: prompt,
        maxTokens: 320,
        temperature: 0.3,
      );
      return parse(raw);
    } catch (e) {
      debugPrint('Notes quiz question failed: $e');
      return null;
    }
  }

  /// The question in [raw], or null when it isn't a usable one.
  static QuizQuestion? parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final data = jsonDecode(raw.substring(start, end + 1));
      if (data is! Map) return null;
      final question = '${data['question'] ?? ''}'.trim();
      final options = [
        for (final o in (data['options'] as List? ?? const [])) '$o'.trim(),
      ];
      final correct = data['correctIndex'];
      if (question.isEmpty ||
          options.length != 4 ||
          options.any((o) => o.isEmpty) ||
          options.toSet().length != 4 ||
          correct is! num ||
          correct < 0 ||
          correct > 3) {
        return null;
      }
      final explanation = '${data['explanation'] ?? ''}'.trim();
      return QuizQuestion(
        question: question,
        options: options,
        correct: correct.toInt(),
        explanation: explanation,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One subject's quiz as it is being written and answered.
class SubjectQuizState {
  const SubjectQuizState({
    this.questions = const [],
    this.generating = false,
    this.target = 0,
    this.answers = const {},
    this.error,
  });

  final List<QuizQuestion> questions;
  final bool generating;

  /// Questions asked for this round.
  final int target;

  /// Question index → chosen option.
  final Map<int, int> answers;
  final String? error;

  int get score => [
    for (final e in answers.entries)
      if (questions[e.key].correct == e.value) 1,
  ].length;

  bool get finished =>
      !generating && questions.isNotEmpty && answers.length == questions.length;

  SubjectQuizState copyWith({
    List<QuizQuestion>? questions,
    bool? generating,
    int? target,
    Map<int, int>? answers,
    String? error,
    bool clearError = false,
  }) => SubjectQuizState(
    questions: questions ?? this.questions,
    generating: generating ?? this.generating,
    target: target ?? this.target,
    answers: answers ?? this.answers,
    error: clearError ? null : error ?? this.error,
  );
}

/// Kept for the session, so switching tabs doesn't throw a quiz away.
class SubjectQuizNotifier extends FamilyNotifier<SubjectQuizState, String> {
  int _round = 0;

  @override
  SubjectQuizState build(String subjectId) => const SubjectQuizState();

  Future<void> start({int count = 5}) async {
    final round = ++_round;
    state = SubjectQuizState(generating: true, target: count);
    try {
      final notes = await ref.read(subjectNotesProvider(arg).future);
      final subject = await ref.read(subjectByIdProvider(arg).future);
      final questions = <QuizQuestion>[];

      final passages = NotesQuizGenerator.pickPassages(notes, count: count);
      if (passages.isNotEmpty) {
        final engine = await ref.read(engineLoadedProvider.future);
        final generator = NotesQuizGenerator(engine);
        for (final p in passages) {
          final q = await generator.fromPassage(
            p,
            subject: subject?.name ?? arg,
          );
          if (round != _round) return;
          if (q != null) {
            questions.add(q);
            state = state.copyWith(questions: List.of(questions));
          }
        }
      }

      // Built-in subjects without class notes use the curriculum's bank.
      if (questions.isEmpty && subject != null) {
        final bank = [
          for (final u in subject.units)
            for (final l in u.lessons) ...l.quiz,
        ]..shuffle();
        questions.addAll(bank.take(count));
      }
      if (round != _round) return;
      state = state.copyWith(
        questions: questions,
        generating: false,
        error: questions.isEmpty ? 'No questions available' : null,
      );
    } catch (e) {
      if (round != _round) return;
      debugPrint('Subject quiz failed: $e');
      state = state.copyWith(
        generating: false,
        error: state.questions.isEmpty ? 'Quiz unavailable' : null,
      );
    }
  }

  void answer(int index, int option) {
    if (state.answers.containsKey(index)) return;
    state = state.copyWith(answers: {...state.answers, index: option});
  }

  void reset() {
    _round++;
    state = const SubjectQuizState();
  }
}

final subjectQuizProvider =
    NotifierProvider.family<SubjectQuizNotifier, SubjectQuizState, String>(
      SubjectQuizNotifier.new,
    );
