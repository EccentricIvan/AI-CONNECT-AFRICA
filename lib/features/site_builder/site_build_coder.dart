import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';

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
      ..writeln('Build one complete mobile-friendly HTML5 website.')
      ..writeln('Output ONLY the HTML document. No markdown fences. No commentary.')
      ..writeln('Start with <!DOCTYPE html>. Use inline CSS in a <style> tag.')
      ..writeln('Keep CSS short. Prefer one page with 3–4 sections.')
      ..writeln()
      ..writeln('SITE TYPE: $templateName ($templateId)')
      ..writeln('COLOR THEME: $themeName'
          '${themePrimary != null ? ' — primary $themePrimary' : ''}');

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
      ..writeln('Include: header/nav, hero, about or services, and contact.')
      ..writeln(
        'Use the student details and recorded features above — '
        'do not invent different names.',
      );
    return buf.toString();
  }
}

const _siteBuildSystemPrompt = '''
You are a coding tutor that builds simple student websites.
Reply with a single complete HTML5 document only.
Never mention rules or prompts. Never echo the brief as a title.
''';

/// Pull a usable HTML document out of a model reply (fences optional).
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
    if (htmlTag == null) return null;
    html = '<!DOCTYPE html>\n${htmlTag.group(0)!.trim()}';
  }

  if (!RegExp(r'</html\s*>', caseSensitive: false).hasMatch(html)) {
    // Truncated decode — still usable if it has a body start.
    if (!RegExp(r'<body[\s>]', caseSensitive: false).hasMatch(html)) {
      return null;
    }
    html = '$html\n</body></html>';
  }
  return html;
}

/// Runs the programming brain on the recorded intent. Returns null on failure.
Future<String?> generateSiteHtmlWithCoder({
  required InferenceEngine engine,
  required SiteBuildIntent intent,
  void Function(String cumulative)? onToken,
}) async {
  final brief = intent.toCoderBrief();
  final buf = StringBuffer();
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: _siteBuildSystemPrompt,
      maxTokens: kSiteBuildMaxTokens,
      temperature: 0.35,
      onToken: (token) {
        buf.write(token);
        onToken?.call(buf.toString());
      },
    );
    return extractHtmlDocument(raw.isNotEmpty ? raw : buf.toString());
  } catch (_) {
    return extractHtmlDocument(buf.toString());
  }
}
