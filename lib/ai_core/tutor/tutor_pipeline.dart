import 'dart:async';

import 'package:flutter/foundation.dart';

import '../inference/inference_engine.dart';
import '../inference/runtime_config.dart';
import '../../curriculum/curriculum_provider.dart';
import 'conversation_memory.dart';
import 'programming_topic.dart';
import 'school_math.dart';
import 'tutor_contract.dart';
import 'tutor_response.dart';

/// Looks up teacher-uploaded material relevant to [searchText], returning one
/// context block or `''`. See `OfflineRagService.retrieveAcrossSubjects`.
typedef TeacherNotesLookup = Future<String> Function(String searchText);

/// Implements the AI tutor contract:
///   Answer → Clarify → Practice → Apply → Create → Reflect
///
/// Each student message advances the pipeline one stage.
/// The pipeline resets when the student changes topic.
/// When curriculum content is available, it is injected into the
/// prompt so the model teaches from accurate material.
class TutorPipeline {
  TutorPipeline({
    required InferenceEngine engine,
    CurriculumService? curriculum,
    this.systemPrompt = kTutorContract,
    this.maxTokens = kMaxNewTokens,
    this.codingCoach = false,
    this.teacherNotes,
  })  : _engine = engine,
        _curriculum = curriculum;

  final InferenceEngine _engine;
  final CurriculumService? _curriculum;
  final String systemPrompt;
  final int maxTokens;
  final bool codingCoach;

  /// Teacher material search. Null in tests and anywhere without a database;
  /// the tutor then behaves exactly as it did before teacher notes existed.
  final TeacherNotesLookup? teacherNotes;

  CurriculumService? get curriculum => _curriculum;
  TutorStage _nextStage = TutorStage.answer;
  String _currentTopic = '';
  CurriculumMatch? _activeMatch;
  final ConversationMemory _memory = ConversationMemory();
  SchoolMathSolution? _activeMath;
  SchoolMathSolution? _awaitingMath;
  bool _practiceMiss = false;

  /// Process a student message and stream the tutor response.
  /// [onToken] fires with each new token as it arrives.
  /// [safetyNote] is an extra instruction from the emotional safety engine
  /// (e.g. "student sounds discouraged — encourage first").
  /// Returns the complete [TutorResponse] when generation finishes.
  Future<TutorResponse> respond({
    required String studentMessage,
    TokenCallback? onToken,
    String? safetyNote,
    String languageCode = 'en',
    bool useCurriculum = true,
  }) async {
    assert(languageCode.isNotEmpty);
    if (_memory.isCorrection(studentMessage, languageCode: languageCode)) {
      _memory.noteCorrection();
    }
    final continuing =
        _memory.isContinuing(studentMessage, languageCode: languageCode);
    final topic = continuing ? _currentTopic : _detectTopic(studentMessage);
    final switched = !continuing &&
        topic.isNotEmpty &&
        _currentTopic.isNotEmpty &&
        topic != _currentTopic;
    if (switched) {
      _currentTopic = topic;
      _nextStage = TutorStage.answer;
      _activeMatch = null;
      _memory.clear();
      await _engine.resetSession();
    } else if (_currentTopic.isEmpty && topic.isNotEmpty) {
      _currentTopic = topic;
    }

    if (!useCurriculum) {
      _activeMatch = null;
    } else {
      final matched = queryLooksLikeMath(studentMessage)
          ? null
          : _curriculum?.findBestMatchDetailed(studentMessage);
      if (matched != null) {
        _activeMatch = matched;
      } else if (switched) {
        _activeMatch = null;
      }
    }

    final stage = _nextStage;

    final mathReply = _respondWithMath(studentMessage, stage);
    if (mathReply != null) {
      // Do not stream the English worked plan. Formulas stay in
      // WorkedSolution; titles/why are localized after respond() returns.
      // Hints and short coaching lines have no formula block, so those
      // may stream.
      if (mathReply.math == null) {
        onToken?.call(mathReply.text);
      }
      _remember(
        studentMessage,
        mathReply.text,
        verified: mathReply.math != null ? [mathReply.math!.answer] : const [],
        languageCode: languageCode,
      );
      _advanceStage();
      return mathReply;
    }

    final notes = useCurriculum && _activeMatch != null
        ? (codingCoach ||
                isProgrammingSubjectName(_activeMatch?.subjectName)
            ? _curriculum?.buildProgrammingTutorNotes(_activeMatch!)
            : _curriculum?.buildTutorNotes(_activeMatch!))
        : null;
    final classNotes =
        useCurriculum ? await _lookupTeacherNotes(studentMessage) : '';
    final prompt = _buildPrompt(
      studentMessage,
      safetyNote: safetyNote,
      curriculumNotes: notes,
      teacherNotes: classNotes,
      useCurriculum: useCurriculum,
      languageCode: languageCode,
    );

    final buffer = StringBuffer();
    String text;
    try {
      text = await _engine.generate(
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: kTutorTemperature,
        onToken: (token) async {
          buffer.write(token);
          await emitToken(onToken, token);
        },
      );
    } catch (e, st) {
      debugPrint('TutorPipeline.respond failed: $e\n$st');
      text = buffer.toString().trim();
      if (text.isEmpty) {
        text =
            'I hit a brief snag finishing that answer. Please ask again in one short sentence.';
        onToken?.call(text);
      }
    }

    _remember(
      studentMessage,
      text,
      verified: _verifiedFromCurriculum(),
      languageCode: languageCode,
    );

    final followUp = _followUpForStage(stage);
    _advanceStage();

    return TutorResponse(
      stage: stage,
      text: text,
      followUpPrompt: followUp,
      topic: _currentTopic,
      lesson: _activeMatch?.lesson,
    );
  }

  void _advanceStage() {
    const order = TutorStage.values;
    final idx = order.indexOf(_nextStage);
    _nextStage = idx < order.length - 1 ? order[idx + 1] : TutorStage.practice;
  }

  /// Teacher material for this turn, or `''`.
  ///
  /// Searches with the matched syllabus lesson's own title and key terms as
  /// well as the student's words. The full-text index matches words, not
  /// meanings, so a student asking "how do plants make food" would miss notes
  /// that only say "photosynthesis" — but the curriculum matcher has already
  /// mapped that question to the photosynthesis lesson, whose vocabulary does
  /// hit. Bounded by a timeout: this is an enhancement and must never hold up
  /// a reply.
  Future<String> _lookupTeacherNotes(String studentMessage) async {
    final lookup = teacherNotes;
    if (lookup == null) return '';
    final lesson = _activeMatch?.lesson;
    final searchText = [
      if (lesson != null) lesson.title,
      if (lesson != null) ...lesson.keyTerms.keys,
      studentMessage,
    ].join(' ');
    try {
      return await lookup(searchText)
          .timeout(const Duration(milliseconds: 600), onTimeout: () => '');
    } catch (e) {
      debugPrint('Teacher notes lookup failed: $e');
      return '';
    }
  }

  static String _clip(String text, int max) =>
      text.length > max ? '${text.substring(0, max - 1)}…' : text;

  String _buildPrompt(
    String studentMessage, {
    String? safetyNote,
    String? curriculumNotes,
    String teacherNotes = '',
    bool useCurriculum = true,
    String languageCode = 'en',
  }) {
    final raw = studentMessage.trim();
    final cap = codingCoach ? 1200 : 280;
    final q = _memory.resolveCurrent(
      raw.length > cap ? '${raw.substring(0, cap)}…' : raw,
      languageCode: languageCode,
    );

    // Curriculum and teacher notes share ONE 700-char slot. The engines clip
    // an over-long prompt from the end, and the student's question is last —
    // so extra notes on top of the slot would cut the question, not the notes.
    final curriculum = curriculumNotes?.trim() ?? '';
    final classNotes = teacherNotes.trim();
    final String notes;
    if (!useCurriculum) {
      notes = 'CURRICULUM: bypassed.\nINSTRUCTION: $kOpenWorldInstruction';
    } else if (curriculum.isEmpty && classNotes.isEmpty) {
      notes =
          'CURRICULUM: none matched.\nINSTRUCTION: $kOpenWorldInstruction';
    } else if (classNotes.isEmpty) {
      notes = 'CURRICULUM:\n${_clip(curriculum, 700)}\n'
          'INSTRUCTION: $kCurriculumHybridInstruction';
    } else if (curriculum.isEmpty) {
      notes = "TEACHER'S NOTES:\n${_clip(classNotes, 700)}\n"
          'INSTRUCTION: $kTeacherNotesOnlyInstruction';
    } else {
      notes = 'CURRICULUM:\n${_clip(curriculum, 400)}\n'
          "TEACHER'S NOTES:\n${_clip(classNotes, 300)}\n"
          'INSTRUCTION: $kCurriculumHybridInstruction '
          '$kTeacherNotesInstruction';
    }
    // Style lives mainly in the pinned system contract — keep this turn short
    // so prefill stays under llama.cpp n_batch on Windows.
    final replyShape = codingCoach
        ? 'REPLY: English. Paragraphs by default; bullets for steps. Fenced code. No thinking narration.'
        : 'REPLY: English. Paragraphs by default; bullets only for lists/steps/named concepts. No thinking narration.';
    final memoryBudget = codingCoach ? 900 : 720;
    return '''$notes
$replyShape
${safetyNote != null ? '$safetyNote\n' : ''}${_memory.promptBlock(maxChars: memoryBudget)}CURRENT: $q
/no_think
Tutor:''';
  }

  void _remember(
    String studentMessage,
    String tutorText, {
    List<String> verified = const [],
    String languageCode = 'en',
  }) {
    _memory.remember(
      student: studentMessage,
      tutor: tutorText,
      verified: verified,
      languageCode: languageCode,
    );
  }

  List<String> _verifiedFromCurriculum() {
    final lesson = _activeMatch?.lesson;
    if (lesson == null) return const [];
    return lesson.keyTerms.entries
        .take(4)
        .map((e) => '${e.key}: ${e.value}')
        .toList();
  }

  String _followUpForStage(TutorStage stage) {
    if (codingCoach) {
      switch (stage) {
        case TutorStage.answer:
          return 'Try changing one value in the example and tell me what happens.';
        case TutorStage.clarify:
          return 'In your own words, what does that line of code do?';
        case TutorStage.practice:
          return 'Paste your attempt — I will check it.';
        case TutorStage.apply:
          return 'Where would you use this in a real program?';
        case TutorStage.create:
          return 'Write a tiny program that uses this idea.';
        case TutorStage.reflect:
          return 'What is one thing you can now do in code that you could not before?';
      }
    }
    // No static chrome under chat bubbles — the model owns the closing
    // question when one is needed. Math/coding paths set their own prompts.
    switch (stage) {
      case TutorStage.answer:
      case TutorStage.clarify:
      case TutorStage.practice:
      case TutorStage.apply:
      case TutorStage.create:
      case TutorStage.reflect:
        return '';
    }
  }

  String _detectTopic(String message) {
    final lower = message.toLowerCase();

    const topicKeywords = <String, List<String>>{
      'mathematics': ['math', 'algebra', 'equation', 'fraction', 'geometry', 'calculus', 'arithmetic', 'percentage', 'ratio', 'number'],
      'physics': ['physics', 'gravity', 'force', 'energy', 'motion', 'electricity', 'magnet', 'wave', 'light', 'newton'],
      'biology': ['biology', 'cell', 'photosynthesis', 'dna', 'gene', 'ecosystem', 'organ', 'evolution', 'species', 'bacteria'],
      'chemistry': ['chemistry', 'atom', 'element', 'reaction', 'acid', 'base', 'molecule', 'compound', 'periodic', 'bond'],
      'programming': ['python', 'code', 'program', 'function', 'variable', 'loop', 'debug', 'algorithm', 'software', 'script'],
      'web_development': ['html', 'css', 'javascript', 'website', 'web dev', 'webpage', 'frontend', 'responsive', 'dom', 'flexbox'],
      'app_development': ['app dev', 'mobile app', 'flutter', 'android', 'ios', 'widget', 'navigation', 'ui design', 'ux', 'deploy'],
      'ai_data': ['ai', 'artificial intelligence', 'machine learning', 'data science', 'neural', 'deep learning', 'model', 'dataset', 'training data'],
      'entrepreneurship': ['business', 'entrepreneur', 'startup', 'marketing', 'sales', 'profit', 'investor', 'revenue', 'branding'],
      'agriculture': ['agriculture', 'farm', 'crop', 'soil', 'irrigation', 'livestock', 'harvest', 'seed', 'fertilizer', 'poultry'],
      'history': ['history', 'war', 'colonial', 'empire', 'revolution', 'civilization', 'ancient', 'medieval', 'independence'],
      'geography': ['geography', 'climate', 'continent', 'river', 'mountain', 'population', 'urban', 'map', 'earthquake', 'volcano'],
      'english_writing': ['writing', 'essay', 'grammar', 'paragraph', 'sentence', 'punctuation', 'vocabulary', 'tense', 'noun', 'verb'],
      'economics': ['economics', 'economy', 'supply', 'demand', 'inflation', 'gdp', 'trade', 'tax', 'price', 'market economy'],
      'arts': ['art', 'painting', 'drawing', 'sculpture', 'color theory', 'sketch', 'design', 'photography', 'creative', 'canvas'],
    };

    String bestTopic = '';
    int bestScore = 0;

    for (final entry in topicKeywords.entries) {
      int score = 0;
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestTopic = entry.key;
      }
    }

    if (bestScore > 0) return bestTopic;
    return '';
  }

  /// Analyzes the recent conversation to produce a real summary (for the
  /// student memory engine's "compressed summary" requirement, instead of
  /// blindly truncating the latest reply) plus an optional detected
  /// strength/weakness. Best-effort — falls back to an empty summary if
  /// generation fails or produces something unparseable.
  Future<SessionAnalysis> analyzeSession() async {
    if (_memory.isEmpty) return const SessionAnalysis(summary: '');

    final convo = _memory.analysisTranscript(maxTurns: 6);
    if (convo.isEmpty) return const SessionAnalysis(summary: '');

    final prompt = '''Analyze this tutoring conversation briefly.
$convo

Respond in exactly this format:
SUMMARY: <one short sentence, max 20 words, what the student learned or discussed>
STRENGTH: <one short phrase describing something the student did well, or NONE>
WEAKNESS: <one short phrase describing something the student is struggling with, or NONE>''';

    try {
      final raw = await _engine.generate(
        prompt: prompt,
        maxTokens: 80,
        temperature: kTutorTemperature,
      );
      return _parseAnalysis(raw);
    } catch (_) {
      return const SessionAnalysis(summary: '');
    }
  }

  SessionAnalysis _parseAnalysis(String raw) {
    String? extract(String label) {
      final match = RegExp('$label:\\s*(.+)', caseSensitive: false).firstMatch(raw);
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty || value.toUpperCase().startsWith('NONE')) {
        return null;
      }
      return value;
    }

    final summary = extract('SUMMARY') ??
        (raw.length > 150 ? '${raw.substring(0, 150)}…' : raw);

    return SessionAnalysis(
      summary: summary,
      strength: extract('STRENGTH'),
      weakness: extract('WEAKNESS'),
    );
  }

  /// Reset pipeline (e.g. user starts a new session).
  /// Where this pipeline currently stands, for persisting a session.
  String get currentTopic => _currentTopic;
  TutorStage get nextStage => _nextStage;

  /// Snapshot the compressed chat memory so a session can be reopened.
  Map<String, Object?> memorySnapshot() => _memory.toJson();

  /// Reopen a previously saved session.
  ///
  /// Order matters: [_engine.resetSession] is awaited FIRST and only then is
  /// [_memory] seeded. The engine has its own conversation state, and the
  /// memory re-enters the next prompt through [ConversationMemory.promptBlock],
  /// so seeding before the reset would both wipe what was just restored and
  /// double-count the history that survived in the engine.
  Future<void> restoreSession({
    required Map<String, Object?> memory,
    required String topic,
    required TutorStage nextStage,
  }) async {
    await _engine.resetSession();
    _memory.clear();
    _activeMatch = null;
    _clearMath();
    _memory.restoreFrom(memory);
    _currentTopic = topic;
    _nextStage = nextStage;
  }

  void reset() {
    _nextStage = TutorStage.answer;
    _currentTopic = '';
    _activeMatch = null;
    _memory.clear();
    _activeMath = null;
    _awaitingMath = null;
    _practiceMiss = false;
    unawaited(_engine.resetSession());
  }

  void _clearMath() {
    _activeMath = null;
    _awaitingMath = null;
    _practiceMiss = false;
  }

  TutorResponse? _respondWithMath(String studentMessage, TutorStage stage) {
    final follow = _mathFollowUp(studentMessage, stage);
    if (follow != null) return follow;

    final solved = solveSchoolMath(studentMessage);
    if (solved == null) return null;

    if (wantsMathHint(studentMessage) && !wantsFullMathSteps(studentMessage)) {
      _activeMath = solved;
      _awaitingMath = solved;
      return TutorResponse(
        stage: stage,
        text: solved.hintMessage,
        followUpPrompt: 'Try it, then tell me your answer.',
        topic: _currentTopic.isEmpty ? 'mathematics' : _currentTopic,
        mathCoach: true,
        lesson: _activeMatch?.lesson,
      );
    }

    return _emitWorked(solved, stage);
  }

  TutorResponse? _mathFollowUp(String studentMessage, TutorStage stage) {
    if (_activeMath == null && _awaitingMath == null) return null;

    if (!isMathCoachingFollowUp(studentMessage)) {
      if (solveSchoolMath(studentMessage) == null &&
          !_memory.isContinuing(studentMessage)) {
        _clearMath();
      }
      return null;
    }

    final target = _awaitingMath ?? _activeMath;
    if (target == null) return null;

    if (wantsMathHint(studentMessage)) {
      return TutorResponse(
        stage: stage,
        text: target.hintMessage,
        followUpPrompt: 'Try it, then tell me your answer.',
        topic: 'mathematics',
        mathCoach: true,
        lesson: _activeMatch?.lesson,
      );
    }

    if (wantsFullMathSteps(studentMessage)) {
      final show = _practiceMiss
          ? (_awaitingMath ?? _activeMath)
          : (_activeMath ?? _awaitingMath);
      _practiceMiss = false;
      if (show == null) return null;
      return _emitWorked(show, stage);
    }

    final attempt = extractNumericAttempt(studentMessage);
    if (attempt == null) return null;
    final expected = target.numericAnswer;
    if (expected == null) return null;

    if (nearlyEqual(attempt, expected)) {
      _practiceMiss = false;
      final next = solveSchoolMath(target.practiceQuestion);
      _activeMath = target;
      _awaitingMath = next;
      return TutorResponse(
        stage: TutorStage.practice,
        text: "That's right — ${target.answer}. Here is the method so it sticks:",
        followUpPrompt: next == null
            ? 'Want another problem like this?'
            : 'Your turn — try this: ${target.practiceQuestion}',
        topic: 'mathematics',
        math: target,
        mathCoach: true,
        lesson: _activeMatch?.lesson,
      );
    }

    _practiceMiss = true;
    return TutorResponse(
      stage: TutorStage.practice,
      text: "Not quite. ${target.hintMessage}",
      followUpPrompt: 'Have another go, or ask me to show the full steps.',
      topic: 'mathematics',
      mathCoach: true,
      lesson: _activeMatch?.lesson,
    );
  }

  TutorResponse _emitWorked(SchoolMathSolution solved, TutorStage stage) {
    _activeMath = solved;
    _awaitingMath = solveSchoolMath(solved.practiceQuestion);
    return TutorResponse(
      stage: stage,
      text: solved.fullPlan,
      followUpPrompt: 'Your turn — try this: ${solved.practiceQuestion}',
      topic: _currentTopic.isEmpty ? 'mathematics' : _currentTopic,
      math: solved,
      mathCoach: true,
      lesson: _activeMatch?.lesson,
    );
  }
}

class SessionAnalysis {
  const SessionAnalysis({required this.summary, this.strength, this.weakness});
  final String summary;
  final String? strength;
  final String? weakness;
}
