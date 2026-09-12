/// Keeps Qwen3's reasoning block out of the student's bubble.
///
/// Qwen3 is a thinking model: it may open a `<think>` span before it answers.
/// The tutor prompt asks it not to (`/no_think` in `TutorPipeline`), but the
/// switch is a soft one — the model still emits an *empty* `<think>\n\n
/// </think>` pair much of the time, and ignores the switch outright often
/// enough to matter. `flutter_gemma`'s own `ModelThinkingFilter` only handles
/// `ModelType.deepSeek` and passes Qwen straight through, so without this the
/// tags reach the UI as literal text.
///
/// Tokens arrive one at a time and a tag can be split across several of them
/// (`<`, `think`, `>`), so this holds text back until it can tell whether a
/// think block is starting. A Qwen3 reasoning span is always at the very
/// start of a reply, so once the first real text is out the filter stops
/// buffering and streams straight through.
class ThinkTagFilter {
  static const _open = '<think>';
  static const _close = '</think>';

  final StringBuffer _held = StringBuffer();
  bool _inThink = false;
  bool _passthrough = false;

  /// True once any real answer text has reached the student this reply.
  bool _sawVisible = false;

  /// Reasoning kept only so a runaway span cannot grow the hold buffer.
  final StringBuffer _thinkText = StringBuffer();
  static const _salvageCap = 2000;

  /// Set once a span closes: the blank lines Qwen3 puts between `</think>`
  /// and the answer arrive as their own tokens, so they have to be dropped
  /// after the tag is gone, not just inside it. Otherwise every reply opens
  /// with the whitespace that used to surround the reasoning.
  bool _stripLead = false;

  /// Feeds one streamed token in; returns the text safe to display now
  /// (often empty while a tag is still being decided).
  String add(String token) {
    if (_passthrough) return _emit(token);
    _held.write(token);
    return _drain();
  }

  String _emit(String text) {
    final clean = _withoutMarker(text);
    if (clean.isEmpty) return '';
    if (!_stripLead) {
      _sawVisible = true;
      return clean;
    }
    final trimmed = clean.trimLeft();
    if (trimmed.isEmpty) return '';
    _stripLead = false;
    _sawVisible = true;
    return trimmed;
  }

  /// Text carried over between tokens because it might be the start of
  /// [_marker] — the marker can be split the same way a tag can.
  String _markerTail = '';

  /// The switch `TutorPipeline` puts in the prompt to turn reasoning off.
  /// Whether LiteRT-LM's Qwen3 template consumes it or echoes it back is
  /// the runtime's business; either way a student must never read it.
  static const _marker = '/no_think';

  String _withoutMarker(String text) {
    var s = _markerTail + text;
    _markerTail = '';
    s = s.replaceAll(_marker, '');
    final dangling = _danglingPrefix(s, _marker);
    if (dangling.isNotEmpty) {
      _markerTail = dangling;
      return s.substring(0, s.length - dangling.length);
    }
    return s;
  }

  /// Call when the stream ends: releases anything still held.
  ///
  /// An unterminated `<think>` is dropped. Surfacing that span painted the
  /// model's monologue into the student bubble.
  String flush() {
    if (_inThink) {
      _held.clear();
      _thinkText.clear();
      _markerTail = '';
      return '';
    }
    if (_passthrough) {
      // Release whatever was being held back as a possible partial marker.
      final tail = _markerTail;
      _markerTail = '';
      return tail == _marker ? '' : tail;
    }
    final rest = _held.toString();
    _held.clear();
    _passthrough = true;
    return _emit(rest);
  }

  String _drain() {
    final text = _held.toString();

    if (_inThink) {
      final end = text.indexOf(_close);
      if (end < 0) {
        // Still inside the span. Keep only a tail that could be the start of
        // the closing tag, so the buffer cannot grow with reasoning text.
        final keep = _danglingPrefix(text, _close);
        if (!_sawVisible && _thinkText.length < _salvageCap) {
          _thinkText.write(text.substring(0, text.length - keep.length));
        }
        _held
          ..clear()
          ..write(keep);
        return '';
      }
      final after = text.substring(end + _close.length);
      _inThink = false;
      _passthrough = true;
      _stripLead = true;
      _held.clear();
      return _emit(after);
    }

    final start = text.indexOf(_open);
    if (start >= 0) {
      final before = text.substring(0, start);
      _inThink = true;
      _held
        ..clear()
        ..write(text.substring(start + _open.length));
      return _emit(before) + _drain();
    }

    // No opening tag yet. Hold only while the text so far could still turn
    // into one; anything else is ordinary output and ends the buffering.
    final trimmed = text.trimLeft();
    // Nothing but whitespace so far — a `<think>` may still be coming, and
    // leading blank lines are not worth streaming on their own.
    if (trimmed.isEmpty) return '';
    if (_danglingPrefix(text, _open) == trimmed) return '';
    _held.clear();
    _passthrough = true;
    return _emit(text);
  }

  /// The longest suffix of [text] that is a proper prefix of [tag] — the
  /// part that might still become a full tag once more tokens arrive.
  static String _danglingPrefix(String text, String tag) {
    final max = text.length < tag.length - 1 ? text.length : tag.length - 1;
    for (var len = max; len > 0; len--) {
      if (tag.startsWith(text.substring(text.length - len))) {
        return text.substring(text.length - len);
      }
    }
    return '';
  }
}
