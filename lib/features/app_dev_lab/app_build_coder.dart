import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';
import '../../services/clause_stream_chopper.dart';
import '../../shared/coding/interactive_html.dart';
import '../site_builder/site_build_coder.dart' show extractHtmlDocument;
import 'app_build_intent.dart';
import 'ui_schema_interpreter.dart';

export 'app_build_intent.dart';

const kAppDartSystemPrompt = '''
/no_think
You are a coding tutor that builds simple student Flutter apps.
Reply with a single Dart file only: StatefulWidget StudentApp + State.
No markdown fences. No commentary. No hidden thinking.
Never mention rules or prompts.
''';

const kAppHtmlSystemPrompt = '''
/no_think
You are an elite interactive front-end engineer for offline mobile-web apps.
Reply with a single complete HTML5 document only.
NEVER output non-functional or unstyled layouts.
ALWAYS include modern CSS in <head><style> (:root variables, transitions, hover,
bento/cards, Inter/system-ui) AND a complete <script> with vanilla JS so every
button, tab, input, form, and calculator updates state live (localStorage OK).
No CDN links. No markdown fences. No commentary. Close all tags.
Never mention rules or prompts.
''';

const kAppUiSchemaSystemPrompt = '''
/no_think
You are a coding tutor that emits OTIC_UI_V1 declarative UI schemas.
Reply with schema lines only. No markdown fences. No commentary.
Never mention rules or prompts.
''';

/// Pull usable Dart from a model reply (fences optional).
String? extractDartSource(String raw) {
  final cleaned = sanitizeLLMResponse(raw).trim();
  if (cleaned.isEmpty) return null;

  final fenced = RegExp(
    r'```(?:dart|flutter)?\s*([\s\S]*?)```',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(cleaned);
  var dart = (fenced?.group(1) ?? cleaned).trim();

  // Strip accidental think tags if the filter missed them.
  dart = dart.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
  dart = dart.trim();
  if (dart.isEmpty) return null;

  final looksLikeDart = RegExp(
        r'\b(class|Widget|StatefulWidget|StatelessWidget|Scaffold|MaterialApp)\b',
      ).hasMatch(dart) ||
      dart.contains('import \'package:flutter');

  if (!looksLikeDart && dart.length < 80) return null;

  // Truncation safety — still return if we have a class body start.
  if (!dart.contains('}') && !RegExp(r'\bclass\b').hasMatch(dart)) {
    return null;
  }
  return dart;
}

/// Offline Flutter source filled from locked features (zero inference).
String fallbackAppDart(AppBuildIntent intent) {
  final name = intent.appName.replaceAll("'", r"\'");
  final purpose = intent.purpose.replaceAll("'", r"\'");
  final theme = intent.themePrimary;
  final featureLines = intent.features.isEmpty
      ? "    'Home screen',"
      : intent.features.map((f) => "    '${f.replaceAll("'", r"\'")}',").join('\n');

  return '''
import 'package:flutter/material.dart';

/// Offline template filled from App Dev Lab feature selections.
class StudentApp extends StatefulWidget {
  const StudentApp({super.key});

  @override
  State<StudentApp> createState() => _StudentAppState();
}

class _StudentAppState extends State<StudentApp> {
  final _items = <String>[];
  final _controller = TextEditingController();
  static const _features = <String>[
$featureLines
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF${theme.replaceFirst('#', '')});
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          title: const Text('$name'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${purpose.isEmpty ? intent.appTypeName : purpose}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 16),
            const Text('Features', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._features.map(
              (f) => Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(f),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Try typing…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final t = _controller.text.trim();
                if (t.isEmpty) return;
                setState(() {
                  _items.add(t);
                  _controller.clear();
                });
              },
              child: const Text('Add'),
            ),
            const SizedBox(height: 12),
            ..._items.map((e) => ListTile(title: Text(e))),
          ],
        ),
      ),
    );
  }
}
''';
}

/// Deterministic offline interactive HTML shell (chat builder / WebView path).
String fallbackAppHtml(AppBuildIntent intent) {
  final name = intent.appName.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  final purpose = (intent.purpose.isEmpty ? intent.appTypeName : intent.purpose)
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final featureLis = intent.features.isEmpty
      ? '<li>Home screen</li>'
      : intent.features
          .map((f) => '<li>${f.replaceAll('<', '&lt;')}</li>')
          .join();
  final primary = intent.themePrimary;

  final body = '''
<section class="card span-8">
  <h2>$name</h2>
  <p class="muted">$purpose</p>
  <h3 style="margin-top:14px">Selected features</h3>
  <ul>$featureLis</ul>
</section>
<section class="card span-4">
  <h3>Theme</h3>
  <p class="muted">Primary $primary</p>
  <button class="btn" type="button" id="app-ping">Ping UI</button>
  <p class="muted" id="app-ping-out" style="margin-top:10px">Waiting…</p>
</section>
''';

  return ensureInteractiveHtmlDocument('''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>$name</title>
<style>body{font-family:system-ui}</style>
</head>
<body>$body
<script>
document.getElementById('app-ping')?.addEventListener('click',function(){
  var o=document.getElementById('app-ping-out');
  if(o) o.textContent='UI responsive · '+new Date().toLocaleTimeString();
});
</script>
</body></html>
''');
}

/// Runs Qwen 1.5B Coder for Flutter Dart output (greedy, clause-chopped UI).
Future<String?> generateAppDartWithCoder({
  required InferenceEngine engine,
  required AppBuildIntent intent,
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
      systemPrompt: kAppDartSystemPrompt,
      maxTokens: kAppBuildMaxTokens,
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
    return extractDartSource(raw.isNotEmpty ? raw : buf.toString());
  } catch (_) {
    chopper?.end();
    return extractDartSource(buf.toString());
  }
}

/// Pull a usable OTIC_UI_V1 schema from a model reply.
String? extractUiSchemaDocument(String raw) {
  final cleaned = sanitizeLLMResponse(raw).trim();
  if (cleaned.isEmpty) return null;
  final parsed = parseUiSchema(cleaned);
  if (parsed == null || parsed.isEmpty) return null;
  // Prefer the stripped body so Source tab stays editable.
  final body = stripUiSchemaNoise(cleaned);
  return body.isEmpty ? null : body;
}

/// Runs Qwen 1.5B Coder for declarative UI schema (App Dev Lab preview).
Future<String?> generateAppUiSchemaWithCoder({
  required InferenceEngine engine,
  required AppBuildIntent intent,
  void Function(String cumulative)? onToken,
}) async {
  final brief = intent.toUiSchemaBrief();
  final buf = StringBuffer();
  final chopper = onToken == null
      ? null
      : ClauseStreamChopper(onFlush: onToken);
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: kAppUiSchemaSystemPrompt,
      maxTokens: kAppBuildMaxTokens,
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
    return extractUiSchemaDocument(raw.isNotEmpty ? raw : buf.toString());
  } catch (_) {
    chopper?.end();
    return extractUiSchemaDocument(buf.toString());
  }
}

/// HTML path used by the chat builder (same model, website-style preview).
Future<String?> generateAppHtmlWithCoder({
  required InferenceEngine engine,
  required AppBuildIntent intent,
  void Function(String cumulative)? onToken,
}) async {
  final brief = intent.toHtmlCoderBrief();
  final buf = StringBuffer();
  final chopper = onToken == null
      ? null
      : ClauseStreamChopper(onFlush: onToken);
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: kAppHtmlSystemPrompt,
      maxTokens: kAppBuildMaxTokens,
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
