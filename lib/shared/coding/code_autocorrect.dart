import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';

enum CodeAutocorrectKind { html, python, dart }

/// Instant offline fixes students often need in the manual editors.
String applyHeuristicAutocorrect(String source, CodeAutocorrectKind kind) {
  var code = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Smart quotes → ASCII (paste from Word / chat).
  code = code
      .replaceAll('\u201C', '"')
      .replaceAll('\u201D', '"')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u00A0', ' ');

  switch (kind) {
    case CodeAutocorrectKind.python:
      return _fixPython(code);
    case CodeAutocorrectKind.html:
      return _fixHtml(code);
    case CodeAutocorrectKind.dart:
      return _fixDart(code);
  }
}

String _fixDart(String code) {
  var out = code;
  out = out.replaceAllMapped(
    RegExp(r'\bStatlessWidget\b'),
    (_) => 'StatelessWidget',
  );
  out = out.replaceAllMapped(
    RegExp(r'\bStatefullWidget\b'),
    (_) => 'StatefulWidget',
  );
  out = out.replaceAll(
    "import 'package:flutter/materail.dart'",
    "import 'package:flutter/material.dart'",
  );
  out = out.replaceAll(
    'import "package:flutter/materail.dart"',
    "import 'package:flutter/material.dart'",
  );
  return out;
}

String _fixPython(String code) {
  final lines = code.split('\n');
  final out = <String>[];
  for (var line in lines) {
    // Common print typos (word boundary-ish).
    line = line.replaceAllMapped(
      RegExp(r'\b(pritn|pirnt|prnit|Print)\s*\('),
      (_) => 'print(',
    );
    line = line.replaceAllMapped(
      RegExp(r'\b(ture|TURE)\b'),
      (_) => 'True',
    );
    line = line.replaceAllMapped(
      RegExp(r'\b(flase|FALSE|Falsee)\b'),
      (_) => 'False',
    );
    line = line.replaceAllMapped(
      RegExp(r'\b(none|NONE)\b'),
      (m) {
        // Don't rewrite comments that say "none".
        if (line.trimLeft().startsWith('#')) return m.group(0)!;
        return 'None';
      },
    );
    // == vs = in if/while (very common student slip): if x = 1 → if x == 1
    line = line.replaceAllMapped(
      RegExp(r'^(\s*(?:if|elif|while)\s+.+?)\s=\s([^=].*)$'),
      (m) => '${m[1]} == ${m[2]}',
    );
    // Balance a trailing open ( for print(… without )
    final openParens = '('.allMatches(line).length;
    final closeParens = ')'.allMatches(line).length;
    if (openParens > closeParens &&
        !line.trimLeft().startsWith('#') &&
        line.contains('print(')) {
      line = '$line${')' * (openParens - closeParens)}';
    }
    // Odd number of " on a non-comment line → close the string.
    if (!line.trimLeft().startsWith('#')) {
      final quotes = '"'.allMatches(line).length;
      if (quotes.isOdd) {
        final trimmed = line.trimRight();
        if (trimmed.endsWith(')')) {
          final i = line.lastIndexOf(')');
          line = '${line.substring(0, i)}"${line.substring(i)}';
        } else {
          line = '$line"';
        }
      }
    }
    out.add(line);
  }
  return out.join('\n');
}

String _fixHtml(String code) {
  var html = code;
  html = html.replaceAll(RegExp(r'</?\s*br\s*/?\s*>', caseSensitive: false), '<br>');
  html = html.replaceAllMapped(
    RegExp(r'<!doctype\s+html>', caseSensitive: false),
    (_) => '<!DOCTYPE html>',
  );

  // Close a few void-safe paired tags if left open (simple stack).
  final voidTags = {
    'br', 'hr', 'img', 'input', 'meta', 'link', 'source', 'area', 'base', 'col',
    'embed', 'param', 'track', 'wbr',
  };
  final pairable = {
    'html', 'head', 'body', 'title', 'div', 'span', 'p', 'h1', 'h2', 'h3', 'h4',
    'h5', 'h6', 'ul', 'ol', 'li', 'a', 'section', 'header', 'footer', 'nav',
    'main', 'article', 'style', 'script', 'button', 'form', 'table', 'tr', 'td',
    'th', 'strong', 'em', 'b', 'i',
  };

  final stack = <String>[];
  final tagRe = RegExp(r'<(/?)([a-zA-Z][\w-]*)([^>]*)>', multiLine: true);
  for (final m in tagRe.allMatches(html)) {
    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();
    final rest = m.group(3) ?? '';
    if (voidTags.contains(name) || rest.trimRight().endsWith('/')) continue;
    if (!pairable.contains(name)) continue;
    if (closing) {
      if (stack.isNotEmpty && stack.last == name) {
        stack.removeLast();
      } else {
        // Mismatched close — ignore for heuristic pass.
      }
    } else {
      stack.add(name);
    }
  }
  if (stack.isNotEmpty) {
    final closers = stack.reversed.map((t) => '</$t>').join('');
    html = html.trimRight();
    if (!html.endsWith('\n')) html = '$html\n';
    html = '$html$closers\n';
  }
  return html;
}

/// Strip fences if the coder wraps the fix in ```…
String extractCorrectedCode(String raw) {
  final cleaned = sanitizeLLMResponse(raw).trim();
  if (cleaned.isEmpty) return '';
  final fenced = RegExp(
    r'```(?:\w+)?\s*([\s\S]*?)```',
    multiLine: true,
  ).firstMatch(cleaned);
  if (fenced != null) return fenced.group(1)!.trim();
  return cleaned;
}

const _fixSystem = '''
You fix student code for an offline coding lab.
Return ONLY the corrected source code.
No markdown fences. No explanations. No titles.
Keep the student's intent and lesson structure.
''';

/// Heuristic pass, then optional 1.5B coder polish.
Future<String> autocorrectCode({
  required String source,
  required CodeAutocorrectKind kind,
  InferenceEngine? engine,
  bool useCoder = true,
}) async {
  final heuristic = applyHeuristicAutocorrect(source, kind);
  if (!useCoder || engine == null || !engine.isReady) {
    return heuristic;
  }

  final lang = switch (kind) {
    CodeAutocorrectKind.python => 'python',
    CodeAutocorrectKind.html => 'html',
    CodeAutocorrectKind.dart => 'dart',
  };
  final prompt = '''
Fix syntax and small mistakes in this $lang code.
Return ONLY the full corrected code.

CODE:
$heuristic
''';

  try {
    final raw = await engine.generate(
      prompt: prompt,
      systemPrompt: _fixSystem,
      maxTokens: kCodeFixMaxTokens,
      temperature: 0.1,
      onToken: (_) {},
    );
    final fixed = extractCorrectedCode(raw);
    if (fixed.isEmpty || fixed.length < heuristic.length * 0.4) {
      return heuristic;
    }
    // Reject replies that look like prose instead of code.
    if (kind == CodeAutocorrectKind.python &&
        !fixed.contains('print') &&
        !fixed.contains('=') &&
        !heuristic.contains('print')) {
      return heuristic;
    }
    if (kind == CodeAutocorrectKind.html &&
        !fixed.toLowerCase().contains('<') &&
        heuristic.contains('<')) {
      return heuristic;
    }
    if (kind == CodeAutocorrectKind.dart &&
        !fixed.contains('Widget') &&
        !fixed.contains('class') &&
        heuristic.contains('class')) {
      return heuristic;
    }
    return applyHeuristicAutocorrect(fixed, kind);
  } catch (_) {
    return heuristic;
  }
}
