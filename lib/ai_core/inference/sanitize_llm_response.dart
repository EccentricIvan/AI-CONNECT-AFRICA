import 'think_tag_filter.dart';

/// Accumulates streamed tokens, hides think-spans, and only emits text that
/// [sanitizeLLMResponse] would keep. Used so the chat bubble never paints a
/// preamble that is later stripped.
class SanitizedTokenStream {
  final _filter = ThinkTagFilter();
  final _raw = StringBuffer();
  String _shown = '';

  String add(String token) {
    final visible = _filter.add(token);
    if (visible.isEmpty) return '';
    _raw.write(visible);
    return _delta();
  }

  String flush() {
    final tail = _filter.flush();
    if (tail.isNotEmpty) _raw.write(tail);
    return _delta();
  }

  String get text => sanitizeLLMResponse(_raw.toString()).trim();

  /// Forward-only deltas. When cleaning shrinks the visible string (preamble
  /// stripped), emit nothing — callers append, and cumulative sinks like
  /// [ChatInferencePipeline] re-run [sanitizeLLMResponse] on the full buffer.
  String _delta() {
    final cleaned = sanitizeLLMResponse(_raw.toString());
    if (cleaned == _shown) return '';
    if (cleaned.startsWith(_shown)) {
      final extra = cleaned.substring(_shown.length);
      _shown = cleaned;
      return extra;
    }
    // Shrink / rewrite — do not append a second copy of the answer.
    _shown = cleaned;
    return '';
  }
}

/// Strips Qwen reasoning so a student never sees the model's monologue.
///
/// [ThinkTagFilter] hides `<think>` tags token-by-token. This cleaner is the
/// second pass for a complete (or cumulative) string: leftover tags, a
/// trailing `</think>`, `/no_think`, and the "Okay, let's see…" preamble
/// Qwen 0.6B writes when it ignores the thinking switch.
///
/// Trailing whitespace is kept so streamed token boundaries (e.g. `"Plants "`)
/// are not collapsed mid-reply. Callers that want a final bubble string should
/// `.trim()` the result.
String sanitizeLLMResponse(String rawText) {
  if (rawText.isEmpty) return rawText;

  // 1. Remove explicit <think>...</think> tags.
  var cleaned = rawText.replaceAll(
    RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false),
    '',
  );

  // 2. Handle unmatched trailing </think> tags.
  if (RegExp(r'</think>', caseSensitive: false).hasMatch(cleaned)) {
    cleaned = cleaned.split(RegExp(r'</think>', caseSensitive: false)).last;
  }

  // Drop an unclosed <think>… span (stream cut off mid-reasoning).
  final open = RegExp(r'<think>', caseSensitive: false).firstMatch(cleaned);
  if (open != null) {
    cleaned = cleaned.substring(0, open.start).replaceFirst(RegExp(r'\s+$'), '');
  }

  cleaned = cleaned.replaceAll(RegExp(r'/no_think', caseSensitive: false), '');
  // Marker often sits after a space; drop the orphaned trailing space(s).
  if (RegExp(r'/no_think', caseSensitive: false).hasMatch(rawText)) {
    cleaned = cleaned.replaceFirst(RegExp(r'[ \t]+$'), '');
  }

  // Leading junk left by removed think blocks / markers.
  cleaned = cleaned.replaceFirst(RegExp(r'^\s+'), '');

  // 3. Fallback: strip common meta-reasoning prefixes.
  final metaPatterns = [
    RegExp(r'^(Okay,?\s*let\x27?s\s*see\b[\s\S]*?\n\n)', caseSensitive: false),
    RegExp(r'^(The student is asking[\s\S]*?\n\n)', caseSensitive: false),
    RegExp(r'^(Okay,?\s+the user is asking[\s\S]*?\n\n)', caseSensitive: false),
    RegExp(r'^(Let me think\b[\s\S]*?\n\n)', caseSensitive: false),
  ];

  for (final pattern in metaPatterns) {
    if (pattern.hasMatch(cleaned)) {
      cleaned = cleaned.replaceFirst(pattern, '');
      cleaned = cleaned.replaceFirst(RegExp(r'^\s+'), '');
    }
  }

  // Qwen 0.6B often writes the whole reply as one reasoning paragraph and
  // never emits `\n\n`. Hide that rather than paint it in the bubble.
  if (!cleaned.contains('\n\n') &&
      _isBareReasoningPreamble(cleaned.trimRight())) {
    return '';
  }

  return cleaned;
}

bool _isBareReasoningPreamble(String text) {
  const openers = [
    r'^Okay,?\s+let\x27?s\s+see\b',
    r'^Okay,?\s+the user is asking\b',
    r'^The student is asking\b',
    r'^Let me think\b',
  ];
  for (final source in openers) {
    if (RegExp(source, caseSensitive: false).hasMatch(text)) return true;
  }
  return false;
}
