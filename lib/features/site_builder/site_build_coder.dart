import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';
import '../../services/clause_stream_chopper.dart';
import '../../shared/coding/interactive_html.dart';

/// Compact brief of every feature the student picked before tapping Build.
///
/// Sent to the 1.5B coder so generation starts already knowing their intent.
class SiteBuildIntent {
  SiteBuildIntent({
    required this.templateId,
    required this.templateName,
    required this.themeName,
    required this.themePrimary,
    required this.answers,
    required this.content,
  });

  final String templateId;
  final String templateName;
  final String themeName;
  final String? themePrimary;

  /// Fields the student typed (name, phone, …).
  final Map<String, String> answers;

  /// Auto-picked copy recorded at build time (tagline, about, …).
  final Map<String, String> content;

  /// Prompt the coder sees — features only, no full template HTML (ctx budget).
  String toCoderBrief() {
    final buf = StringBuffer()
      ..writeln('/no_think')
      ..writeln(
        'Build ONE complete offline HTML5 website. Output ONLY the HTML document.',
      )
      ..writeln('No markdown fences. No commentary. Start with <!DOCTYPE html>.')
      ..writeln()
      ..writeln('DESIGN RULES (mandatory):')
      ..writeln(
        '- Build the site the student described below. Do not add features '
        'they did not ask for.',
      )
      ..writeln(
        '- Include a self-contained modern CSS system in <head><style>…</style> '
        'with :root color variables, smooth transitions, hover states, '
        'Inter/system-ui fonts and soft shadows.',
      )
      ..writeln(
        '- Add a <script> block ONLY for interactivity this site actually '
        'needs (a nav toggle, a form that validates). Wire it with '
        'addEventListener. A page that needs no JavaScript must not have any.',
      )
      ..writeln(
        '- Fully offline — NO CDN links, NO external scripts/fonts/CSS.',
      )
      ..writeln(
        '- Sections appropriate to this site type: nav, hero, the content '
        'sections a $templateName needs, contact details, footer.',
      )
      ..writeln()
      ..writeln('SITE TYPE: $templateName ($templateId)')
      ..writeln(
        'COLOR THEME: $themeName'
        '${themePrimary != null ? ' — primary $themePrimary' : ''}',
      );

    if (answers.isNotEmpty) {
      buf.writeln();
      buf.writeln('STUDENT DETAILS:');
      for (final e in answers.entries) {
        buf.writeln('- ${e.key}: ${e.value}');
      }
    }
    if (content.isNotEmpty) {
      buf.writeln();
      buf.writeln('RECORDED CONTENT FEATURES:');
      for (final e in content.entries) {
        buf.writeln('- ${e.key}: ${e.value}');
      }
    }
    buf
      ..writeln()
      ..writeln(
        'Use the student details and recorded features above — '
        'do not invent different names.',
      )
      ..writeln(
        'Close every <style> and <script> tag completely before </html>.',
      );
    return buf.toString();
  }
}

const _siteBuildSystemPrompt = '''
/no_think
You are a front-end engineer building offline student websites.
Reply with a single complete HTML5 document only.
Include a modern CSS design system in <head><style> (:root variables,
transitions, hover effects, grid, Inter/system-ui).
Add JavaScript only where the page genuinely needs it, wired with
addEventListener. Never add sample widgets the brief did not ask for.
No CDN links. No markdown fences. No commentary.
Close all tags. Never mention rules or prompts. Never echo the brief as a title.
''';

/// Pull a usable, interactive HTML document out of a model reply.
String? extractHtmlDocument(String raw) {
  final cleaned = sanitizeLLMResponse(raw).trim();
  if (cleaned.isEmpty) return null;

  final fenced = RegExp(
    r'```(?:html|HTML)?\s*([\s\S]*?)```',
    multiLine: true,
  ).firstMatch(cleaned);
  var html = (fenced?.group(1) ?? cleaned).trim();

  final doctype = RegExp(
    r'<!DOCTYPE\s+html[\s\S]*',
    caseSensitive: false,
  ).firstMatch(html);
  if (doctype != null) {
    html = doctype.group(0)!.trim();
  } else {
    final htmlTag = RegExp(
      r'<html[\s\S]*',
      caseSensitive: false,
    ).firstMatch(html);
    if (htmlTag == null) {
      // A fragment carrying real markup is salvageable. Prose is not: a
      // refusal or an explanation must return null so the caller falls back
      // to its deterministic build, rather than being wrapped in a document
      // and presented to the student as their website.
      if (!RegExp(r'<[a-zA-Z][^>]*>').hasMatch(html)) return null;
      return ensureRenderableHtmlDocument(html);
    }
    html = '<!DOCTYPE html>\n${htmlTag.group(0)!.trim()}';
  }

  return ensureRenderableHtmlDocument(html);
}

/// Runs the programming brain on the recorded intent. Returns null on failure.
Future<String?> generateSiteHtmlWithCoder({
  required InferenceEngine engine,
  required SiteBuildIntent intent,
  void Function(String cumulative)? onToken,
}) async {
  final brief = intent.toCoderBrief();
  final buf = StringBuffer();
  final chopper = onToken == null
      ? null
      : ClauseStreamChopper(onFlush: onToken);
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: _siteBuildSystemPrompt,
      maxTokens: kSiteBuildMaxTokens,
      temperature: kCoderTemperature,
      onToken: (token) {
        buf.write(token);
        if (chopper != null) {
          chopper.add(token);
        } else {
          onToken?.call(buf.toString());
        }
      },
    );
    chopper?.end();
    return extractHtmlDocument(raw.isNotEmpty ? raw : buf.toString());
  } catch (_) {
    chopper?.end();
    return extractHtmlDocument(buf.toString());
  }
}
