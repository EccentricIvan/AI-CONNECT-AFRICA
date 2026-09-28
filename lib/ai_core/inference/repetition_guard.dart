/// Stops a reply that has fallen into a decoder loop — the small brain,
/// decoding near-greedily, can start writing the same paragraph over and
/// over until it runs out of tokens.
///
/// Sits between an engine's cleaned token stream and the student. Text
/// streams through unchanged, except that a sentence which *begins* like one
/// already written is held back until it is complete: if it turns out to be
/// an exact repeat, the guard trips, the repeat is never shown, and the
/// engine stops reading the model. If it diverges, it is released.
///
/// Only prose is checked. Code inside ``` fences is passed through
/// untouched, and a reply that starts like markup or data (`<`, `{`, `[`) —
/// a site/app build, a JSON quiz — is not guarded at all, since repeated
/// lines are normal there.
class RepetitionGuard {
  /// A sentence must be at least this long (normalized) to count — short
  /// ones ("Great question.", "Yes.") repeat legitimately.
  static const _minSentenceChars = 30;

  /// A partial sentence is compared once it is this long; shorter prefixes
  /// ("The ") would hold back nearly everything.
  static const _minPrefixChars = 16;

  final _text = StringBuffer();
  final _seen = <String>{};
  int _emitted = 0;

  /// Start of the sentence not yet complete.
  int _sentenceStart = 0;
  bool? _enabled;
  bool _tripped = false;

  /// True once a repeat was caught. The caller should stop generating.
  bool get tripped => _tripped;

  /// Everything shown so far — the reply, with any repeat cut off.
  String get text => _text.toString().substring(0, _emitted);

  /// Feeds [chunk]; returns the part that is safe to show now.
  String add(String chunk) {
    if (_tripped || chunk.isEmpty) return '';
    _text.write(chunk);
    final all = _text.toString();

    _enabled ??= _decide(all);
    if (_enabled == null) return ''; // only whitespace so far
    if (_enabled == false) return _release(all.length);

    // Close every sentence that has ended.
    for (;;) {
      final end = _nextSentenceEnd(all, _sentenceStart);
      if (end == null) break;
      final start = _sentenceStart;
      _sentenceStart = end;
      if (_insideFence(all, start)) continue;
      final key = _normalize(all.substring(start, end));
      if (key.length < _minSentenceChars) continue;
      if (!_seen.add(key)) {
        _tripped = true;
        return _release(_trimBack(all, start));
      }
    }

    // Hold the open sentence while it could still become a repeat.
    final start = _sentenceStart;
    if (!_insideFence(all, start)) {
      final partial = _normalize(all.substring(start));
      if (partial.length >= _minPrefixChars &&
          _seen.any((s) => s.startsWith(partial))) {
        return _release(start);
      }
    }
    return _release(all.length);
  }

  /// Anything still held when the model finishes normally.
  String flush() => _tripped ? '' : _release(_text.length);

  String _release(int upTo) {
    if (upTo <= _emitted) return '';
    final out = _text.toString().substring(_emitted, upTo);
    _emitted = upTo;
    return out;
  }

  /// Null until there is non-whitespace text to judge by.
  static bool? _decide(String all) {
    final t = all.trimLeft();
    if (t.isEmpty) return null;
    return !(t.startsWith('<') || t.startsWith('{') || t.startsWith('['));
  }

  /// End (exclusive) of the sentence starting at [from]: after `.`, `!`, `?`
  /// followed by whitespace, or at a line break. Null while still open.
  static int? _nextSentenceEnd(String s, int from) {
    for (var i = from; i < s.length; i++) {
      final c = s[i];
      if (c == '\n') return i + 1;
      if ((c == '.' || c == '!' || c == '?') &&
          i + 1 < s.length &&
          (s[i + 1] == ' ' || s[i + 1] == '\n' || s[i + 1] == '\t')) {
        return i + 1;
      }
    }
    return null;
  }

  static bool _insideFence(String s, int at) =>
      '```'.allMatches(s.substring(0, at)).length.isOdd;

  /// Drops the whitespace before the repeat, so the reply ends cleanly.
  static int _trimBack(String s, int at) {
    var i = at;
    while (i > 0 && s[i - 1].trim().isEmpty) {
      i--;
    }
    return i;
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
