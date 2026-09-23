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
You are a front-end engineer building offline mobile-web apps.
Reply with a single complete HTML5 document only.
Include modern CSS in <head><style> (:root variables, transitions, hover,
cards, Inter/system-ui). Add a <script> with vanilla JS for the features the
brief asks for, wired with addEventListener. Never add sample widgets the
brief did not ask for.
No CDN links. No markdown fences. No commentary. Close all tags.
Never mention rules or prompts.
''';

const kAppUiSchemaSystemPrompt = '''
/no_think
You are a coding tutor that emits OTIC_UI_V1 declarative UI schemas.
Reply with schema lines only. No markdown fences. No commentary.
Never mention rules or prompts.
''';

const kAppBackendSystemPrompt = '''
/no_think
You are a backend engineer writing a downloadable FastAPI scaffold.
Reply with a single complete Python file only.
Use FastAPI + Pydantic, in-memory storage, permissive CORS, and a uvicorn
entrypoint. This file is exported for the student to run elsewhere — it is
never executed by this app.
No markdown fences. No commentary. Never mention rules or prompts.
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

  // Self-contained: this document carries every class it uses, so it renders
  // the same whether or not anything downstream touches it.
  return ensureRenderableHtmlDocument('''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$name</title>
<style>
:root{--primary:$primary;--ink:#0f172a;--muted:#64748b;--line:#e2e8f0}
*{box-sizing:border-box}
body{margin:0;padding:24px;background:#f8fafc;color:var(--ink);
  font-family:system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif}
.wrap{max-width:720px;margin:0 auto;display:grid;gap:16px}
.card{background:#fff;border:1px solid var(--line);border-radius:16px;padding:20px;
  box-shadow:0 1px 3px rgba(15,23,42,.06)}
h1{margin:0 0 6px;font-size:24px}
h2{margin:0 0 10px;font-size:16px}
p{margin:0;line-height:1.55}
.muted{color:var(--muted);font-size:14px}
ul{margin:10px 0 0;padding-left:20px;line-height:1.9}
button{border:0;cursor:pointer;border-radius:10px;padding:11px 18px;font-weight:600;
  font-size:14px;background:var(--primary);color:#fff}
button:hover{opacity:.9}
</style>
</head>
<body>
<div class="wrap">
  <section class="card">
    <h1>$name</h1>
    <p class="muted">$purpose</p>
  </section>
  <section class="card">
    <h2>Selected features</h2>
    <ul>$featureLis</ul>
  </section>
  <section class="card">
    <h2>Try it</h2>
    <button type="button" id="app-ping">Ping UI</button>
    <p class="muted" id="app-ping-out" style="margin-top:12px">Waiting…</p>
  </section>
</div>
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

/// Pull usable Python from a model reply (fences optional).
///
/// Returns null on a refusal or bare prose so the caller can leave the
/// backend unset rather than export a file that raises on the first line.
String? extractPythonSource(String raw) {
  final cleaned = sanitizeLLMResponse(raw).trim();
  if (cleaned.isEmpty) return null;

  final fenced = RegExp(
    r'```(?:python|py)?\s*([\s\S]*?)```',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(cleaned);
  var python = (fenced?.group(1) ?? cleaned).trim();

  python = python
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
      .trim();
  if (python.isEmpty) return null;

  final looksLikePython =
      RegExp(r'\b(import|from|def|FastAPI|class)\b').hasMatch(python);
  if (!looksLikePython) return null;

  return python;
}

/// Downloadable FastAPI backend scaffold matching [intent]'s features.
///
/// Export-only (see [AppBuildIntent.toBackendCoderBrief]) — this app never
/// runs the Python it generates.
Future<String?> generateAppBackendWithCoder({
  required InferenceEngine engine,
  required AppBuildIntent intent,
  void Function(String cumulative)? onToken,
}) async {
  final brief = intent.toBackendCoderBrief();
  final buf = StringBuffer();
  final chopper = onToken == null
      ? null
      : ClauseStreamChopper(onFlush: onToken);
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: kAppBackendSystemPrompt,
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
    return extractPythonSource(raw.isNotEmpty ? raw : buf.toString());
  } catch (_) {
    chopper?.end();
    return extractPythonSource(buf.toString());
  }
}
