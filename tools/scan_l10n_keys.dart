// Scans lib/ for every `tr(...)` / `trFill(...)` key and writes the ones that
// no curated table covers to tools/l10n_keys.json — the input
// tools/generate_ui_strings.dart translates.
//
//   dart run tools/scan_l10n_keys.dart          # rewrite l10n_keys.json
//   dart run tools/scan_l10n_keys.dart --check  # exit 1 if it is stale
//
// generate_ui_strings.dart's header calls this "the scanner"; it had never
// been written, so the key list was maintained by hand and drifted behind the
// UI. Every string added by a redesign is invisible to the generator until it
// lands in that file, and `tr()` falls back to English silently, so the drift
// shows up as English text on a Kinyarwanda device rather than as an error.
import 'dart:convert';
import 'dart:io';

/// Matches a key line inside a curated table: `'Home': 'Nyumbani',`
final _curatedEntry = RegExp(r"""^\s*(['"])((?:[^'"\\]|\\.)*)\1\s*:\s*['"]""");

/// `tr(` / `trFill(` not preceded by an identifier character, so `attr(` and
/// friends do not match.
final _callSite = RegExp(r'(?<![A-Za-z0-9_$])(trFill|tr)\s*\(');

void main(List<String> args) {
  final curated = <String>{}
    ..addAll(_curatedKeys('lib/l10n/ui_strings.dart'))
    ..addAll(_curatedKeys('lib/l10n/ui_strings_more.dart'));

  final used = <String>{};
  for (final file in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    // The tables themselves are data, not call sites.
    if (file.path.contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}')) {
      continue;
    }
    used.addAll(_keysIn(file.readAsStringSync()));
  }

  final out = File('tools/l10n_keys.json');

  // Union, never replace. The list predates this scanner and also carries
  // strings that are still hardcoded in a `Text(...)` rather than wrapped in
  // `tr()` — queued for translation against the day the widget is converted.
  // Those have no call site to find, so rewriting the file from the scan
  // alone would silently drop them.
  final existing = out.existsSync()
      ? (jsonDecode(out.readAsStringSync()) as List).cast<String>().toSet()
      : <String>{};

  final discovered = used.difference(curated).difference(existing);
  final missing = existing.union(used.difference(curated)).toList()..sort();
  final rendered = '${const JsonEncoder.withIndent('  ').convert(missing)}\n';

  if (args.contains('--check')) {
    if (discovered.isNotEmpty) {
      stderr.writeln('${discovered.length} tr() key(s) missing from '
          'tools/l10n_keys.json — run: dart run tools/scan_l10n_keys.dart');
      for (final k in discovered.toList()..sort()) {
        stderr.writeln('  + $k');
      }
      exit(1);
    }
    stdout.writeln('tools/l10n_keys.json covers every tr() key '
        '(${missing.length} queued)');
    return;
  }

  out.writeAsStringSync(rendered);
  stdout.writeln('${used.length} tr() keys in lib/, ${curated.length} already '
      'curated, ${discovered.length} newly discovered, '
      '${missing.length} queued -> tools/l10n_keys.json');
  for (final k in discovered.toList()..sort()) {
    stdout.writeln('  + $k');
  }
}

Set<String> _curatedKeys(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};
  return file
      .readAsLinesSync()
      .map(_curatedEntry.firstMatch)
      .whereType<RegExpMatch>()
      .map((m) => _unescape(m.group(2)!))
      // Language codes ('sw', 'lg', …) open a sub-map, not a key/value pair,
      // and never match because they are followed by `{`, not a quote.
      .toSet();
}

Set<String> _keysIn(String source) {
  final keys = <String>{};
  for (final call in _callSite.allMatches(source)) {
    var i = call.end;
    // Both helpers take the BuildContext first; the key is the next argument.
    final comma = source.indexOf(',', i);
    if (comma < 0) continue;
    i = comma + 1;
    final key = _readStringLiteral(source, i);
    if (key != null && key.trim().isNotEmpty) keys.add(key);
  }
  return keys;
}

/// Reads a Dart string literal at/after [start], joining adjacent literals
/// (`'a'\n'b'`) the way the compiler does. Returns null for a non-literal
/// argument — a variable or a nested call, which cannot be a static key.
String? _readStringLiteral(String source, int start) {
  final buffer = StringBuffer();
  var i = start;
  var found = false;

  while (i < source.length) {
    final ch = source[i];
    if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') {
      i++;
      continue;
    }
    if (ch != "'" && ch != '"') break;

    final quote = ch;
    i++;
    final literal = StringBuffer();
    while (i < source.length && source[i] != quote) {
      if (source[i] == r'\' && i + 1 < source.length) {
        literal.write(source[i]);
        literal.write(source[i + 1]);
        i += 2;
        continue;
      }
      literal.write(source[i]);
      i++;
    }
    if (i >= source.length) return null;
    i++; // closing quote

    // An interpolated literal is built at runtime, so it is not a table key.
    if (literal.toString().contains(r'$')) return null;
    buffer.write(literal);
    found = true;
  }

  return found ? _unescape(buffer.toString()) : null;
}

String _unescape(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\\', r'\');
