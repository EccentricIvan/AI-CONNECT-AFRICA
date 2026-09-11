import 'dart:async';

import '../science/science_text.dart';

/// Yield so the UI isolate can paint between native decode bursts.
Future<void> yieldToEventLoop() => Future<void>.delayed(Duration.zero);

/// One ready unit of English (or bypassed math) for AfriSLM / the UI.
class CascadeSpan {
  const CascadeSpan({
    required this.text,
    required this.bypassTranslation,
  });

  final String text;
  final bool bypassTranslation;
}

/// Accumulates inbound AfriSLM English tokens and signals when Qwen may start.
class EnglishIngestBuffer {
  final StringBuffer _buf = StringBuffer();
  final _ready = Completer<String>();
  bool _closed = false;

  String get snapshot => _buf.toString();
  bool get isClosed => _closed;

  void add(String chunk) {
    if (_closed || chunk.isEmpty) return;
    _buf.write(chunk);
    _maybeReady();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) {
      _ready.complete(_buf.toString());
    }
  }

  void _maybeReady() {
    if (_ready.isCompleted) return;
    final t = _buf.toString().trim();
    if (t.isEmpty) return;
    final sentenceEnd = RegExp(r'[.!?…]\s*$').hasMatch(t) || t.contains('\n');
    if (sentenceEnd && t.length >= 8) {
      _ready.complete(_buf.toString());
      return;
    }
    if (t.length >= 80) {
      _ready.complete(_buf.toString());
    }
  }

  /// First complete clause, or the full buffer when inbound ends.
  Future<String> waitForReasoningPrompt() => _ready.future;
}

/// Regex filter that splits a token stream into math-bypass vs prose clauses.
class FormulaBypassTransformer
    extends StreamTransformerBase<String, CascadeSpan> {
  const FormulaBypassTransformer();

  @override
  Stream<CascadeSpan> bind(Stream<String> stream) async* {
    final pending = StringBuffer();
    await for (final token in stream) {
      pending.write(token);
      for (final piece in takeReadyTranslationChunks(pending)) {
        for (final span in _spans(piece)) {
          yield span;
          await yieldToEventLoop();
        }
      }
    }
    for (final piece in takeReadyTranslationChunks(pending, flush: true)) {
      for (final span in _spans(piece)) {
        yield span;
        await yieldToEventLoop();
      }
    }
  }

  Iterable<CascadeSpan> _spans(String piece) {
    final trimmed = piece.trim();
    if (trimmed.isEmpty) {
      return [CascadeSpan(text: piece, bypassTranslation: true)];
    }
    if (isMathPassThrough(trimmed)) {
      return [
        CascadeSpan(
          text: repairUnclosedMathDelimiters(trimmed),
          bypassTranslation: true,
        ),
      ];
    }
    final islands = protectMathIslands(piece);
    if (islands.slots.isEmpty) {
      return [CascadeSpan(text: trimmed, bypassTranslation: false)];
    }
    final out = <CascadeSpan>[];
    final re = RegExp(r'⟦(\d+)⟧');
    var last = 0;
    final text = islands.text;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        final prose = text.substring(last, m.start);
        if (prose.trim().isNotEmpty) {
          out.add(CascadeSpan(text: prose, bypassTranslation: false));
        }
      }
      final i = int.parse(m.group(1)!);
      out.add(CascadeSpan(
        text: repairUnclosedMathDelimiters(islands.slots[i]),
        bypassTranslation: true,
      ));
      last = m.end;
    }
    if (last < text.length) {
      final prose = text.substring(last);
      if (prose.trim().isNotEmpty) {
        out.add(CascadeSpan(text: prose, bypassTranslation: false));
      }
    }
    return out;
  }
}

/// Join stream chunks without doubling spaces.
String joinCascade(String left, String right) {
  if (left.isEmpty) return right;
  if (right.isEmpty) return left;
  if (left.endsWith(' ') || right.startsWith(' ')) return '$left$right';
  if (RegExp(r'[.!?:,;]$').hasMatch(left)) return '$left $right';
  return '$left$right';
}
