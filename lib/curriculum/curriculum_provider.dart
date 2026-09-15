import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai_core/tutor/school_math.dart';
import 'curriculum_models.dart';

class CurriculumService {
  final Map<String, Subject> _cache = {};

  static const _subjects = [
    'mathematics',
    'physics',
    'biology',
    'chemistry',
    'programming',
    'ai_and_data',
    'entrepreneurship',
    'agriculture',
    'history',
    'geography',
    'english_writing',
    'economics',
    'arts',
    'web_development',
    'app_development',
    'ignite_ai',
  ];

  /// The bundled subject ids, readable from outside.
  ///
  /// Additive alias for [_subjects] — the list itself is unchanged. Exposed so
  /// `CustomSubjectService` can refuse to create a teacher subject whose slug
  /// would collide with a shipped one.
  static const bundledSubjectIds = _subjects;

  Future<List<Subject>> loadAll() async {
    if (_cache.length == _subjects.length) return _cache.values.toList();
    for (final id in _subjects) {
      if (!_cache.containsKey(id)) {
        try {
          final json = await rootBundle.loadString('assets/curriculum/$id.json');
          final data = jsonDecode(json) as Map<String, dynamic>;
          _cache[id] = Subject.fromJson(data);
        } catch (_) {}
      }
    }
    return _cache.values.toList();
  }

  Future<Subject?> load(String subjectId) async {
    if (_cache.containsKey(subjectId)) return _cache[subjectId];
    try {
      final json =
          await rootBundle.loadString('assets/curriculum/$subjectId.json');
      final data = jsonDecode(json) as Map<String, dynamic>;
      final subject = Subject.fromJson(data);
      _cache[subjectId] = subject;
      return subject;
    } catch (_) {
      return null;
    }
  }

  Lesson? findLesson(String subjectId, String query) {
    final subject = _cache[subjectId];
    if (subject == null) return null;
    final q = query.toLowerCase();
    for (final unit in subject.units) {
      for (final lesson in unit.lessons) {
        if (lesson.title.toLowerCase().contains(q)) return lesson;
        for (final term in lesson.keyTerms.keys) {
          if (_containsWord(q, term.toLowerCase())) return lesson;
        }
      }
    }
    return null;
  }

  /// True if [word] appears in [text] as a whole word (not mid-word, e.g.
  /// "tell" must not match inside "intelligence").
  bool _containsWord(String text, String word) {
    return RegExp('\\b${RegExp.escape(word)}').hasMatch(text);
  }

  Lesson? findBestMatch(String query) => findBestMatchDetailed(query)?.lesson;

  static String _normalizeForMatch(String text) {
    return text
        .toLowerCase()
        .replaceAll('≤', '<=')
        .replaceAll('≥', '>=')
        .replaceAll(RegExp(r'[^\w\s=<>]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  CurriculumMatch? findBestMatchDetailed(String query) {
    if (queryLooksLikeMath(query)) return null;
    final qLower = query.toLowerCase();
    final qNorm = _normalizeForMatch(query);
    final words = qNorm.split(' ').where((w) => w.length > 3).toList();
    if (words.isEmpty && qNorm.isEmpty) return null;

    CurriculumMatch? best;
    int bestScore = 0;

    for (final subject in _cache.values) {
      for (final unit in subject.units) {
        for (final lesson in unit.lessons) {
          int score = 0;
          final titleLower = lesson.title.toLowerCase();

          if (titleLower.length >= 4 && qLower.contains(titleLower)) {
            score += 20;
          }
          for (final word in words) {
            if (_containsWord(titleLower, word)) score += 5;
          }
          for (final term in lesson.keyTerms.keys) {
            final termLower = term.toLowerCase();
            if (termLower.length <= 3) continue;
            if (_containsWord(qLower, termLower) ||
                _containsWord(qNorm, termLower)) {
              score += 3;
            }
          }
          for (final item in lesson.quiz) {
            final quizNorm = _normalizeForMatch(item.question);
            if (quizNorm.isNotEmpty && qNorm == quizNorm) score += 12;
          }

          if (score > bestScore) {
            bestScore = score;
            best = CurriculumMatch(
              subjectName: subject.name,
              unitTitle: unit.title,
              lesson: lesson,
            );
          }
        }
      }
    }

    // Two key terms (3+3) or a title word + key term (5+3) is enough.
    if (bestScore >= 6) return best;
    return null;
  }

  /// Short notes for the on-device tutor. Keep this tight — long dumps
  /// make CPU prefill slow.
  String buildTutorNotes(CurriculumMatch match) {
    final lesson = match.lesson;
    final buf = StringBuffer()
      ..writeln('Subject: ${match.subjectName}')
      ..writeln('Topic: ${match.unitTitle} / ${lesson.title}');
    if (lesson.keyTerms.isNotEmpty) {
      final terms = lesson.keyTerms.entries.take(3).map((e) => '${e.key}: ${e.value}').join('; ');
      buf.writeln('Definitions: $terms');
    }
    final content = lesson.content.length > 360
        ? '${lesson.content.substring(0, 360)}…'
        : lesson.content;
    buf.writeln(content);
    if (lesson.examples.isNotEmpty) {
      final ex = lesson.examples.first;
      buf.writeln('Example: ${ex.length > 140 ? '${ex.substring(0, 140)}…' : ex}');
    }
    return buf.toString().trim();
  }

  /// Tighter notes for the coding chatbot: definitions, one example,
  /// and one practice question so the 1.5B stays on this lesson.
  String buildProgrammingTutorNotes(CurriculumMatch match) {
    final lesson = match.lesson;
    final buf = StringBuffer()
      ..writeln('Subject: ${match.subjectName}')
      ..writeln('Lesson: ${match.unitTitle} / ${lesson.title}')
      ..writeln('CHAT: teach this lesson one beat at a time.');
    if (lesson.keyTerms.isNotEmpty) {
      final terms = lesson.keyTerms.entries
          .take(4)
          .map((e) => '${e.key}: ${e.value}')
          .join('; ');
      buf.writeln('Definitions: $terms');
    }
    final content = lesson.content.length > 420
        ? '${lesson.content.substring(0, 420)}…'
        : lesson.content;
    buf.writeln(content);
    for (final ex in lesson.examples.take(2)) {
      final line = ex.length > 160 ? '${ex.substring(0, 160)}…' : ex;
      buf.writeln('Example: $line');
    }
    if (lesson.quiz.isNotEmpty) {
      buf.writeln('Practice: ${lesson.quiz.first.question}');
    }
    return buf.toString().trim();
  }

  String buildContext(Lesson lesson) {
    final buf = StringBuffer();
    buf.writeln('Topic: ${lesson.title}');
    final content = lesson.content.length > 1600
        ? '${lesson.content.substring(0, 1600)}...'
        : lesson.content;
    buf.writeln(content);
    for (final example in lesson.examples.take(2)) {
      buf.writeln('Example: $example');
    }
    return buf.toString();
  }
}

class CurriculumMatch {
  const CurriculumMatch({
    required this.subjectName,
    required this.unitTitle,
    required this.lesson,
  });

  final String subjectName;
  final String unitTitle;
  final Lesson lesson;
}

final curriculumServiceProvider =
    Provider<CurriculumService>((ref) => CurriculumService());

final allSubjectsProvider = FutureProvider<List<Subject>>((ref) {
  return ref.watch(curriculumServiceProvider).loadAll();
});
