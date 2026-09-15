import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';
import '../../services/hybrid_model_orchestrator.dart';
import 'code_autocorrect.dart' show CodeAutocorrectKind;

const _instructionEditSystem = '''
/no_think
You restyle a student's offline webpage.
The student names ONE visual change ("center the heading", "make the buttons
blue", "bigger text"). Reply with ONLY the CSS rules that make that change.
No <style> tags. No HTML. No markdown fences. No explanation.
End every declaration with !important so it overrides the existing page.
Prefer the selectors listed as already present on the page.
Keep it under six rules.
''';

/// Applies a plain-English restyle instruction ("center the text", "change
/// the color to blue") to [source] and returns the updated document.
///
/// The model is asked only for a short CSS patch, which is appended as a
/// `<style>` override before `</head>` — never for a rewrite of the whole
/// document. That matters on this hardware: [kCodeFixMaxTokens] is far too
/// small to reproduce a full page, so a whole-document round trip would
/// truncate every time, and a bad reply could destroy a working site. An
/// appended override can only ever add style on top of intact markup.
///
/// Returns null when the model is unavailable or its reply isn't usable CSS,
/// in which case callers must leave [source] untouched.
Future<String?> applyCodeInstruction({
  required String source,
  required String instruction,
  required CodeAutocorrectKind kind,
  required InferenceEngine engine,
}) async {
  // CSS patching only makes sense for markup documents.
  if (kind != CodeAutocorrectKind.html) return null;

  final trimmedSource = source.trim();
  final trimmedInstruction = instruction.trim();
  if (!engine.isReady || trimmedSource.isEmpty || trimmedInstruction.isEmpty) {
    return null;
  }

  // Only selector names go in the prompt, never the document — so prompt size
  // stays flat no matter how large the student's page grows.
  final selectors = existingStyleSelectors(trimmedSource);
  final selectorHint = selectors.isEmpty
      ? ''
      : 'SELECTORS ALREADY ON THIS PAGE: ${selectors.join(', ')}\n';

  final prompt = '''
/no_think
$selectorHint
STUDENT REQUEST: $trimmedInstruction
''';

  try {
    final raw = await HybridModelOrchestrator.instance.runExclusive(() {
      return engine.generate(
        prompt: prompt,
        systemPrompt: _instructionEditSystem,
        maxTokens: kCodeFixMaxTokens,
        temperature: kCoderTemperature,
        onToken: (_) {},
      );
    });
    final css = extractCssRules(raw);
    if (css == null) return null;
    return appendStyleOverride(trimmedSource, css);
  } catch (_) {
    return null;
  }
}

/// Distinct selectors already defined in [html]'s first `<style>` block, so
/// the model can target real class names instead of guessing. Capped so the
/// prompt stays small regardless of page size.
List<String> existingStyleSelectors(String html, {int limit = 30}) {
  final styleMatch = RegExp(
    r'<style[^>]*>([\s\S]*?)</style>',
    caseSensitive: false,
  ).firstMatch(html);
  if (styleMatch == null) return const [];

  final css = styleMatch.group(1) ?? '';
  final selectors = <String>{};
  for (final rule in RegExp(r'([^{}]+)\{').allMatches(css)) {
    final head = rule.group(1)!.trim();
    if (head.isEmpty || head.startsWith('@') || head.startsWith(':root')) {
      continue;
    }
    for (final part in head.split(',')) {
      final selector = part.trim();
      if (selector.isEmpty || selector.length > 24) continue;
      selectors.add(selector);
      if (selectors.length >= limit) return selectors.toList();
    }
  }
  return selectors.toList();
}

/// Pulls usable CSS rules out of a model reply, or null when the reply is
/// prose, empty, or a whole document the model was told not to send.
String? extractCssRules(String raw) {
  var cleaned = sanitizeLLMResponse(raw).trim();
  if (cleaned.isEmpty) return null;

  final fenced = RegExp(
    r'```(?:css)?\s*([\s\S]*?)```',
    multiLine: true,
  ).firstMatch(cleaned);
  if (fenced != null) cleaned = (fenced.group(1) ?? '').trim();

  final styleTag = RegExp(
    r'<style[^>]*>([\s\S]*?)</style>',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (styleTag != null) cleaned = (styleTag.group(1) ?? '').trim();

  if (cleaned.isEmpty || !cleaned.contains('{') || !cleaned.contains('}')) {
    return null;
  }
  final lower = cleaned.toLowerCase();
  if (lower.contains('<!doctype') ||
      lower.contains('<html') ||
      lower.contains('<body') ||
      lower.contains('<script')) {
    return null;
  }
  return cleaned;
}

/// Appends [css] as a `<style>` override just before `</head>` so it wins on
/// source order without touching a single line of the student's markup.
String appendStyleOverride(String html, String css) {
  final block = '<style>\n/* AI change */\n$css\n</style>';
  if (html.contains('</head>')) {
    return html.replaceFirst('</head>', '$block\n</head>');
  }
  return '$block\n$html';
}
