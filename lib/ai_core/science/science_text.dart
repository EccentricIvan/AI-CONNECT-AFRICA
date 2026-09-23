/// Chemistry / algebra helpers for streamed tutor text.
///
/// Bare formulas (`H2O`, `CO2`) map to Unicode subscripts. Explicit
/// `$H_2O$` / `$$...$$` spans stay for KaTeX. Unclosed `$$ 4x...` is
/// closed before Markdown sees a raw delimiter.
library;

const _sub = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
};

const _sup = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  '+': '⁺',
  '-': '⁻',
};

/// School-level element symbols. Longest first so `Na` wins over `N`+`a`.
const _elements = r'(?:He|Li|Be|Ne|Na|Mg|Al|Si|Cl|Ar|Ca|Sc|Ti|Cr|Mn|Fe|'
    r'Co|Ni|Cu|Zn|Ga|Ge|As|Se|Br|Kr|Rb|Sr|Zr|Mo|Ag|Cd|Sn|Sb|I|Xe|Ba|'
    r'W|Pt|Au|Hg|Pb|Bi|H|B|C|N|O|F|P|S|K|V)';

final _chemFormula = RegExp(
  '$_elements(?:\\d+$_elements?)+',
);

final _latexChem = RegExp(
  '$_elements(?:_\\{?\\d+\\}?)+$_elements?',
);

final _powerIsland = RegExp(
  r'\b[A-Za-z]\^\d+\b|'
  r'[A-Za-z][\u00B2\u00B3\u00B9\u2070-\u2079]+',
);

final _displayMath = RegExp(r'\$\$[\s\S]*?\$\$');
final _inlineMath = RegExp(r'(?<!\$)\$(?!\$)([^$\n]+)\$(?!\$)');
final _fencedCode = RegExp(r'```[\s\S]*?```');
final _inlineCode = RegExp(r'`[^`\n]+`');

final _wrappedDisplayMath = RegExp(r'^\$\$[\s\S]*\$\$$');
final _wrappedInlineMath = RegExp(r'^\$[^$\n]+\$$');

final _bareEquation = RegExp(
  r'^(?:'
  r'\$\$[\s\S]+?\$\$|'
  r'\$[^$\n]+\$|'
  r'[A-Za-z][A-Za-z0-9]*\s*=\s*[^=\n]{1,80}|'
  r'\d+\s*[a-zA-Z]\s*[+\-/*=].{0,80}=.{0,80}|'
  r'[0-9xX()][0-9xX+\-/*=.\s()^_{}\\]{2,}'
  r')$',
);

final _algebraChunk = RegExp(
  r'(?:'
  r'\d+\s*[a-zA-Z]\s*(?:[+\-/*]|//)\s*'
  r'|\d+[a-zA-Z]'
  r'|[a-zA-Z]\s*=\s*'
  r'|[+\-=]\s*\d+[a-zA-Z]?'
  r')'
  r'[0-9a-zA-Z+\-/*=.\s()^_{}\\]{0,60}',
);

/// Math / LaTeX islands lifted out of a clause so AfriSLM only sees prose.
class MathIslands {
  const MathIslands({
    required this.text,
    required this.slots,
    required this.isPureMath,
  });

  /// Prose with `⟦n⟧` placeholders where formulas used to be.
  final String text;
  final List<String> slots;

  /// True when nothing but formulas / whitespace remains.
  final bool isPureMath;

  String restore(String translated) {
    var out = translated;
    for (var i = 0; i < slots.length; i++) {
      out = out.replaceAll('⟦$i⟧', slots[i]);
      out = out.replaceAll('[[$i]]', slots[i]);
    }
    return out;
  }
}

MathIslands protectMathIslands(String source) {
  if (_isPureFormula(source.trim())) {
    return MathIslands(text: '⟦0⟧', slots: [source], isPureMath: true);
  }
  final slots = <String>[];
  var text = source;

  String slot(String raw) {
    final i = slots.length;
    slots.add(raw);
    return '⟦$i⟧';
  }

  // Code first so `$` inside a snippet is not treated as LaTeX.
  text = text.replaceAllMapped(_fencedCode, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_inlineCode, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_displayMath, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_inlineMath, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_latexChem, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_chemFormula, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_powerIsland, (m) => slot(m.group(0)!));
  text = text.replaceAllMapped(_algebraChunk, (m) {
    final piece = m.group(0)!;
    if (!RegExp(r'[=\d]').hasMatch(piece)) return piece;
    if (!RegExp(r'[+\-/*=]').hasMatch(piece) && !RegExp(r'\d+[a-zA-Z]').hasMatch(piece)) {
      return piece;
    }
    return slot(piece.trim());
  });

  final leftover = text.replaceAll(RegExp(r'⟦\d+⟧'), '').trim();
  final isPure = leftover.isEmpty && slots.isNotEmpty;
  return MathIslands(text: text, slots: slots, isPureMath: isPure);
}

/// Close leaked `$$` / `$` so Markdown never sees a dangling delimiter.
String repairUnclosedMathDelimiters(String text) {
  var out = text;
  final dollars = '\$'.allMatches(out).length;
  if (dollars.isOdd) {
    out = '$out\$';
  }
  final displayOpens = RegExp(r'\$\$').allMatches(out).length;
  if (displayOpens.isOdd) {
    out = '$out\$\$';
  }
  return out;
}

/// Common Unicode operators the model sometimes writes literally instead of
/// as LaTeX commands — flutter_math_fork's KaTeX renders these inconsistently
/// (some fonts show a box/tofu glyph), so they are normalized to the LaTeX
/// spelling, which always renders.
const _texUnicodeOperators = {
  '×': r'\times',
  '÷': r'\div',
  '±': r'\pm',
  '≤': r'\le',
  '≥': r'\ge',
  '≠': r'\neq',
  '≈': r'\approx',
  '·': r'\cdot',
  '−': '-', // U+2212 minus sign, easy to mistake for a hyphen — normalize.
};

/// Cleans one KaTeX source string — the content of a `$...$`/`$$...$$` span
/// from [ScienceSpan.text] — right before it reaches [Math.tex].
///
/// This is *not* a LaTeX formatter: it only removes the specific ways a
/// streamed 1.5B model's math output actually breaks, observed in tutor
/// replies:
///   * Markdown emphasis/code markers leaking into the span (`**x^2**`,
///     `` `ax+b` ``) — legal Markdown around an inline formula, illegal
///     inside the TeX KaTeX actually parses. Only `**`/`__`/`` ` `` are
///     stripped; a bare `_` is left alone because it is real TeX subscript
///     syntax, not emphasis.
///   * A literal two-character `\n` (backslash + n) where the model meant a
///     line break — this reaches Dart as `\n` verbatim when a model streams
///     JSON-escaped output that was never actually decoded, and KaTeX reads
///     it as an undefined control sequence rather than a newline.
///   * Unbalanced `{`/`}` from a stream cut mid-token (partial-turn render,
///     or a truncated reply) — closed rather than left to throw.
///   * Unicode operators standing in for their LaTeX command (see
///     [_texUnicodeOperators]).
///   * Doubled/irregular internal whitespace — cosmetic, but a formula with
///     `a x  ^  2` reads as visibly broken even though KaTeX itself does
///     not error on it.
///
/// Always returns a string, never throws — [Math.tex]'s own
/// `onErrorFallback` remains the last line of defence for anything this
/// does not catch.
String sanitizeTexForRender(String raw) {
  var tex = raw;

  // Markdown emphasis/code that leaked into the math span.
  tex = tex.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');

  // A model that streamed pre-escaped JSON sometimes hands this layer the
  // literal two characters `\` `n` instead of a real newline — replace with
  // a space, not `\\`, since a bare linebreak inside an inline formula reads
  // fine collapsed to whitespace.
  tex = tex.replaceAll(r'\n', ' ').replaceAll(r'\t', ' ');

  // Collapse doubled/irregular whitespace, but keep TeX's own `\ ` (escaped
  // space) and `\quad`/`\qquad` spacing commands intact — only touch plain
  // runs of whitespace.
  tex = tex.replaceAll(RegExp(r'[^\S\n]{2,}'), ' ').trim();

  for (final entry in _texUnicodeOperators.entries) {
    tex = tex.replaceAll(entry.key, entry.value);
  }

  // Balance braces a truncated stream cut off mid-token — appending the
  // missing closers is the only fix that cannot itself corrupt a formula
  // that was already well-formed (nothing is removed or reordered).
  final opens = '{'.allMatches(tex).length;
  final closes = '}'.allMatches(tex).length;
  if (opens > closes) {
    tex = tex + ('}' * (opens - closes));
  }

  return tex;
}

/// True when this chunk must skip AfriSLM (formulas, LaTeX, chemistry, code).
bool isMathPassThrough(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t.startsWith('```') && t.endsWith('```')) return true;
  if (_wrappedDisplayMath.hasMatch(t) || _wrappedInlineMath.hasMatch(t)) {
    return true;
  }
  if (_isPureFormula(t)) return true;
  final islands = protectMathIslands(t);
  if (islands.isPureMath) return true;
  return false;
}

bool _isPureFormula(String t) {
  if (RegExp(r'^(?:[A-Z][a-z]?\d*)+$').hasMatch(t) && RegExp(r'\d').hasMatch(t)) {
    return true;
  }
  if (_chemFormula.hasMatch(t) &&
      t.replaceAll(_chemFormula, '').trim().isEmpty) {
    return true;
  }
  if (_latexChem.hasMatch(t) && t.replaceAll(_latexChem, '').trim().isEmpty) {
    return true;
  }
  if (_powerIsland.hasMatch(t) && t.replaceAll(_powerIsland, '').trim().isEmpty) {
    return true;
  }
  if (t.contains('=') && !RegExp(r'[A-Za-z]{4,}').hasMatch(t)) {
    return true;
  }
  if (_bareEquation.hasMatch(t) && !RegExp(r'[A-Za-z]{4,}').hasMatch(t)) {
    return true;
  }
  return false;
}

class ScienceSpan {
  const ScienceSpan({
    required this.text,
    required this.isMath,
    this.displayMath = false,
  });

  final String text;
  final bool isMath;
  final bool displayMath;
}

/// Split mixed tutor text into KaTeX blocks vs prose for the bubble.
/// Fenced code is kept whole so `$` inside snippets is not treated as math.
List<ScienceSpan> splitScienceSpans(String text) {
  final source = repairUnclosedMathDelimiters(text);
  if (source.isEmpty) return const [];
  final fence = RegExp(r'```[\s\S]*?```');
  if (!fence.hasMatch(source)) {
    return _splitMathSpans(source);
  }
  final spans = <ScienceSpan>[];
  var last = 0;
  for (final m in fence.allMatches(source)) {
    if (m.start > last) {
      spans.addAll(_splitMathSpans(source.substring(last, m.start)));
    }
    spans.add(ScienceSpan(text: m.group(0)!, isMath: false));
    last = m.end;
  }
  if (last < source.length) {
    spans.addAll(_splitMathSpans(source.substring(last)));
  }
  return spans.where((s) => s.text.isNotEmpty).toList();
}

List<ScienceSpan> _splitMathSpans(String source) {
  if (source.isEmpty) return const [];
  final spans = <ScienceSpan>[];
  var i = 0;
  while (i < source.length) {
    final display = source.indexOf(r'$$', i);
    final inlineAt = _nextInlineDollar(source, i);
    final next = _minPositive(display, inlineAt);
    if (next < 0) {
      final rest = source.substring(i);
      if (rest.isNotEmpty) spans.add(ScienceSpan(text: rest, isMath: false));
      break;
    }
    if (next > i) {
      spans.add(ScienceSpan(text: source.substring(i, next), isMath: false));
    }
    if (display == next) {
      final end = source.indexOf(r'$$', next + 2);
      if (end < 0) {
        spans.add(ScienceSpan(
          text: source.substring(next + 2),
          isMath: true,
          displayMath: true,
        ));
        break;
      }
      spans.add(ScienceSpan(
        text: source.substring(next + 2, end),
        isMath: true,
        displayMath: true,
      ));
      i = end + 2;
      continue;
    }
    final end = source.indexOf(r'$', next + 1);
    if (end < 0) {
      spans.add(ScienceSpan(text: source.substring(next + 1), isMath: true));
      break;
    }
    spans.add(ScienceSpan(text: source.substring(next + 1, end), isMath: true));
    i = end + 1;
  }
  return spans.where((s) => s.text.isNotEmpty).toList();
}

int _nextInlineDollar(String source, int from) {
  var i = from;
  while (i < source.length) {
    if (source[i] != r'$') {
      i++;
      continue;
    }
    if (i + 1 < source.length && source[i + 1] == r'$') {
      i += 2;
      continue;
    }
    return i;
  }
  return -1;
}

int _minPositive(int a, int b) {
  if (a < 0) return b;
  if (b < 0) return a;
  return a < b ? a : b;
}

String applyChemistryUnicode(String text) {
  var out = text.replaceAllMapped(_chemFormula, (m) {
    final raw = m.group(0)!;
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      buf.write(_sub[ch] ?? ch);
    }
    return buf.toString();
  });
  out = out.replaceAllMapped(RegExp(r'([A-Za-z])\^(\d+)'), (m) {
    final digits = m.group(2)!.split('').map((d) => _sup[d] ?? d).join();
    return '${m.group(1)}$digits';
  });
  return out;
}

/// Prose gets Unicode chemistry; math spans keep TeX for KaTeX.
String formatScienceProse(String text) => applyChemistryUnicode(text);

/// Pull complete clauses out of a growing English buffer for AfriSLM.
List<String> takeReadyTranslationChunks(StringBuffer buffer, {bool flush = false}) {
  final raw = buffer.toString();
  if (raw.isEmpty) return const [];
  final ready = <String>[];
  var rest = raw;
  final sentence = RegExp(r'[\s\S]*?[.!?…]["”)]*(?:\s+|$)');
  while (rest.isNotEmpty) {
    if (flush && rest.trim().isNotEmpty && !sentence.hasMatch(rest) && rest.length < 8) {
      break;
    }
    final m = sentence.firstMatch(rest);
    if (m != null && RegExp(r'[.!?…]').hasMatch(m.group(0)!)) {
      final chunk = m.group(0)!;
      if (chunk.trim().isNotEmpty) ready.add(chunk.trim());
      rest = rest.substring(chunk.length);
      continue;
    }
    if (rest.contains('\n')) {
      final i = rest.indexOf('\n');
      final left = rest.substring(0, i).trim();
      if (left.isNotEmpty) ready.add(left);
      rest = rest.substring(i + 1);
      continue;
    }
    if (flush) {
      if (rest.trim().isNotEmpty) ready.add(rest.trim());
      rest = '';
      break;
    }
    if (rest.trim().length >= 50) {
      ready.add(rest.trim());
      rest = '';
      break;
    }
    break;
  }
  buffer
    ..clear()
    ..write(rest);
  return ready;
}
