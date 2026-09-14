import '../inference/sanitize_llm_response.dart';
import '../translate/follow_up_glossary.dart';

/// Compressed English chat memory for the tutor prompt (Learn chat).
///
/// Design goals:
/// - Continuity across turns without blowing llama.cpp `n_batch`
/// - Multilingual short follow-ups stay on the last question
/// - Never store local-language student UI text or full transcripts
/// - Reject empty / error / "snag" tutor replies so they do not poison THREAD
/// - Always produce a bounded [promptBlock] even under adversarial growth
class ConversationMemory {
  ConversationMemory({
    this.maxRawTurns = 4,
    this.maxFacts = 6,
    this.turnClipChars = 180,
    this.factClipChars = 90,
    this.digestClipChars = 280,
    this.anchorClipChars = 240,
  }) : assert(maxRawTurns >= 2 && maxRawTurns.isEven);

  /// Raw Student/Tutor lines kept verbatim (always an even count).
  final int maxRawTurns;
  final int maxFacts;
  final int turnClipChars;
  final int factClipChars;
  final int digestClipChars;
  final int anchorClipChars;

  /// Rolling one-line digest of older exchanges folded out of [turns].
  String? lessonDigest;

  /// Last substantive student question (for follow-up resolution).
  String? anchorQuestion;

  final List<({String role, String text})> turns = [];
  final List<String> established = [];

  bool get isEmpty =>
      turns.isEmpty &&
      established.isEmpty &&
      (lessonDigest == null || lessonDigest!.isEmpty);

  int get exchangeCount => turns.length ~/ 2;

  void clear() {
    turns.clear();
    established.clear();
    lessonDigest = null;
    anchorQuestion = null;
  }

  /// Record one English exchange. Returns `false` when the write was rejected
  /// (empty student, transient tutor failure, etc.) so callers can skip stage
  /// side-effects if needed.
  bool remember({
    required String student,
    required String tutor,
    List<String> verified = const [],
    String? languageCode,
  }) {
    final studentClean = _cleanStudent(student, languageCode: languageCode);
    final tutorClean = _cleanTutor(tutor);
    if (studentClean.isEmpty) return false;
    if (tutorClean == null) return false;

    if (_isSubstantiveStudent(studentClean)) {
      anchorQuestion = _clip(studentClean, anchorClipChars);
    }

    turns.add((role: 'student', text: _clip(studentClean, turnClipChars)));
    turns.add((role: 'tutor', text: _clip(tutorClean, turnClipChars)));
    _mergeFacts(verified);
    _foldOverflow();
    return true;
  }

  void _mergeFacts(List<String> verified) {
    for (final raw in verified) {
      final fact = _clip(raw.trim(), factClipChars);
      if (fact.isEmpty) continue;
      final key = _factKey(fact);
      established.removeWhere((e) => _factKey(e) == key);
      established.add(fact);
    }
    if (established.length > maxFacts) {
      established.removeRange(0, established.length - maxFacts);
    }
  }

  static String _factKey(String fact) {
    final i = fact.indexOf(':');
    if (i > 0) return fact.substring(0, i).trim().toLowerCase();
    return fact.toLowerCase();
  }

  void _foldOverflow() {
    while (turns.length > maxRawTurns) {
      final student = turns.removeAt(0).text;
      final tutor = turns.isNotEmpty && turns.first.role == 'tutor'
          ? turns.removeAt(0).text
          : '';
      final bit = tutor.isEmpty
          ? 'Student asked about $student.'
          : 'Student: $student → Tutor: $tutor';
      final prev = lessonDigest?.trim();
      final merged = (prev == null || prev.isEmpty) ? bit : '$prev | $bit';
      lessonDigest = _clip(merged, digestClipChars);
    }
    // Repair odd length if something went wrong — never ship broken THREAD.
    if (turns.length.isOdd) {
      turns.removeLast();
    }
  }

  static String _cleanStudent(String raw, {String? languageCode}) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    final gloss = toEnglishFollowUp(t, langCode: languageCode);
    if (gloss != null) t = gloss;
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Returns cleaned tutor text, or `null` to reject the write.
  static String? _cleanTutor(String raw) {
    final cleaned = sanitizeLLMResponse(raw).trim();
    if (cleaned.isEmpty) return null;
    if (_isTransientFailure(cleaned)) return null;
    return cleaned.replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isTransientFailure(String text) {
    final t = text.toLowerCase();
    return t.contains('brief snag') ||
        t.contains('could not finish that answer') ||
        t.contains('ask again in one short sentence') ||
        t.contains('on-device model is unavailable') ||
        t.contains('generation interrupted') ||
        t.startsWith("couldn't get an answer") ||
        t.startsWith('couldn’t get an answer');
  }

  static bool _isSubstantiveStudent(String text) {
    if (text.length <= 12 && !text.contains('?')) return false;
    final gloss = toEnglishFollowUp(text);
    if (gloss != null && gloss == normalizeFollowUp(text)) {
      // Pure follow-up chip — do not replace the anchor.
      if (text.length <= 24) return false;
    }
    return true;
  }

  static String _clip(String text, int max) {
    if (text.length <= max) return text;
    if (max <= 1) return '…';
    return '${text.substring(0, max - 1)}…';
  }

  bool isContinuing(String message, {String? languageCode}) {
    if (turns.isEmpty &&
        (anchorQuestion == null || anchorQuestion!.isEmpty)) {
      return false;
    }
    final gloss = toEnglishFollowUp(message, langCode: languageCode);
    final t = normalizeFollowUp(gloss ?? message);
    if (t.isEmpty) return false;

    if (_continuingPhrases.contains(t)) return true;
    if (t.startsWith('what about') ||
        t.startsWith('and then') ||
        t.startsWith('tell me more') ||
        t.startsWith('explain') ||
        t.startsWith("i don't understand") ||
        t.startsWith('i dont understand')) {
      return true;
    }
    // Very short follow-ups without a new topic question mark.
    if (t.length <= 12 && !t.contains('?')) return true;
    return false;
  }

  static const _continuingPhrases = {
    'yes', 'yeah', 'yep', 'ok', 'okay', 'sure', 'no',
    'why', 'how', 'what', 'more', 'again', 'example', 'an example',
    'explain', 'explain more', 'continue', 'go on', 'next',
    'and then', 'what about that',
  };

  bool isCorrection(String message, {String? languageCode}) {
    final gloss = toEnglishFollowUp(message, langCode: languageCode);
    final t = (gloss ?? message).trim().toLowerCase();
    return t.contains("that's wrong") ||
        t.contains('that is wrong') ||
        t.contains('incorrect') ||
        t.contains('not true') ||
        t.startsWith('no,') ||
        t.contains('you are wrong') ||
        t.contains('you got it wrong');
  }

  void noteCorrection() {
    if (established.isNotEmpty) established.removeLast();
  }

  String resolveCurrent(String message, {String? languageCode}) {
    final gloss = toEnglishFollowUp(message, langCode: languageCode);
    final resolvedFollowUp = gloss ?? message.trim();
    if (!isContinuing(message, languageCode: languageCode)) {
      return resolvedFollowUp;
    }
    final anchor = anchorQuestion?.trim();
    if (anchor != null && anchor.isNotEmpty) {
      return '$anchor (follow-up: $resolvedFollowUp)';
    }
    for (final turn in turns.reversed) {
      if (turn.role == 'student') {
        return '${turn.text} (follow-up: $resolvedFollowUp)';
      }
    }
    return resolvedFollowUp;
  }

  /// Prompt fragment for the tutor. When [maxChars] is set, shrinks digest
  /// then oldest THREAD lines, then ESTABLISHED — never throws.
  String promptBlock({int? maxChars}) {
    try {
      return _promptBlockUnsafe(maxChars: maxChars);
    } catch (_) {
      // Absolute last resort — chat must stay up.
      final anchor = anchorQuestion;
      if (anchor == null || anchor.isEmpty) return '';
      return 'THREAD:\nStudent: ${_clip(anchor, 120)}\n';
    }
  }

  String _promptBlockUnsafe({int? maxChars}) {
    if (isEmpty) return '';

    final digest = lessonDigest?.trim();
    var threadLines = [
      for (final turn in turns)
        '${turn.role == 'student' ? 'Student' : 'Tutor'}: ${turn.text}',
    ];
    var facts = List<String>.from(established);

    String build({
      required String? dig,
      required List<String> lines,
      required List<String> factLines,
    }) {
      final buf = StringBuffer();
      if (dig != null && dig.isNotEmpty) {
        buf.writeln('DIGEST: $dig');
      }
      if (lines.isNotEmpty) {
        buf.writeln('THREAD:');
        for (final line in lines) {
          buf.writeln(line);
        }
      }
      if (factLines.isNotEmpty) {
        buf.writeln('ESTABLISHED:');
        for (final fact in factLines) {
          buf.writeln('- $fact');
        }
      }
      return buf.toString();
    }

    var block = build(dig: digest, lines: threadLines, factLines: facts);
    if (maxChars == null || block.length <= maxChars) return block;

    // 1) Drop digest.
    block = build(dig: null, lines: threadLines, factLines: facts);
    if (block.length <= maxChars) return block;

    // 2) Drop oldest THREAD pairs until one exchange remains.
    while (threadLines.length > 2 && block.length > maxChars) {
      threadLines = threadLines.sublist(threadLines.length >= 2 ? 2 : 1);
      block = build(dig: null, lines: threadLines, factLines: facts);
    }
    if (block.length <= maxChars) return block;

    // 3) Drop facts from the oldest.
    while (facts.isNotEmpty && block.length > maxChars) {
      facts = facts.sublist(1);
      block = build(dig: null, lines: threadLines, factLines: facts);
    }
    if (block.length <= maxChars) return block;

    // 4) Hard-clip final block, keeping the tail (CURRENT follows this block).
    if (block.length <= maxChars) return block;
    return '…\n${block.substring(block.length - maxChars + 2)}';
  }

  /// Compact view for session analysis / student memory snapshots.
  String analysisTranscript({int maxTurns = 6}) {
    final buf = StringBuffer();
    final dig = lessonDigest?.trim();
    if (dig != null && dig.isNotEmpty) {
      buf.writeln('Earlier: $dig');
    }
    final recent = turns.length > maxTurns
        ? turns.sublist(turns.length - maxTurns)
        : turns;
    for (final t in recent) {
      buf.writeln('${t.role == 'tutor' ? 'Tutor' : 'Student'}: ${t.text}');
    }
    return buf.toString().trim();
  }
}
