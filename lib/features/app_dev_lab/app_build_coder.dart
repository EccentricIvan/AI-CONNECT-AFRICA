import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';
import '../site_builder/site_build_coder.dart' show extractHtmlDocument;
import 'app_build_intent.dart';

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
You are a coding tutor that builds simple student mobile-web apps.
Reply with a single complete HTML5 document only.
No markdown fences. No commentary. No hidden thinking.
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

/// Deterministic offline HTML shell (chat builder / WebView path).
String fallbackAppHtml(AppBuildIntent intent) {
  final name = intent.appName;
  final purpose = intent.purpose;
  final featureLis = intent.features.isEmpty
      ? '<li>Home screen</li>'
      : intent.features.map((f) => '<li>$f</li>').join();
  final primary = intent.themePrimary;

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$name</title>
<style>
*{box-sizing:border-box;margin:0}
body{font-family:Segoe UI,Arial,sans-serif;background:#e5e7eb;min-height:100vh;display:flex;justify-content:center;padding:16px}
.app{width:100%;max-width:420px;background:#fff;border-radius:24px;overflow:hidden;box-shadow:0 12px 40px rgba(0,0,0,.12);min-height:640px;display:flex;flex-direction:column}
.bar{background:$primary;color:#fff;padding:18px 16px}
.bar h1{font-size:20px}
.bar p{opacity:.9;font-size:13px;margin-top:4px}
.screen{padding:16px;flex:1}
.card{background:#f8fafc;border:1px solid #e2e8f0;border-radius:14px;padding:14px;margin-bottom:12px}
.card h2{font-size:15px;margin-bottom:8px;color:#0f172a}
.card ul{padding-left:18px;color:#334155;font-size:14px;line-height:1.6}
.btn{display:inline-block;margin-top:8px;background:$primary;color:#fff;border:none;border-radius:10px;padding:10px 14px;font-weight:600}
input,textarea{width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:10px;margin-top:8px}
</style>
</head>
<body>
<div class="app">
  <div class="bar">
    <h1>$name</h1>
    <p>${purpose.isEmpty ? intent.appTypeName : purpose}</p>
  </div>
  <div class="screen">
    <div class="card">
      <h2>Selected features</h2>
      <ul>$featureLis</ul>
    </div>
    <div class="card">
      <h2>Quick try</h2>
      <input id="note" placeholder="Type something…"/>
      <button class="btn" onclick="document.getElementById('out').textContent=document.getElementById('note').value||'Saved locally in this preview'">Save</button>
      <p id="out" style="margin-top:10px;font-size:13px;color:#475569"></p>
    </div>
  </div>
</div>
</body>
</html>
''';
}

/// Runs Qwen 1.5B Coder (llama.cpp program lane) for Flutter Dart output.
Future<String?> generateAppDartWithCoder({
  required InferenceEngine engine,
  required AppBuildIntent intent,
  void Function(String cumulative)? onToken,
}) async {
  final brief = intent.toCoderBrief();
  final buf = StringBuffer();
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: kAppDartSystemPrompt,
      maxTokens: kAppBuildMaxTokens,
      temperature: 0.35,
      onToken: (token) {
        buf.write(token);
        onToken?.call(buf.toString());
      },
    );
    return extractDartSource(raw.isNotEmpty ? raw : buf.toString());
  } catch (_) {
    return extractDartSource(buf.toString());
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
  try {
    final raw = await engine.generate(
      prompt: brief,
      systemPrompt: kAppHtmlSystemPrompt,
      maxTokens: kAppBuildMaxTokens,
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
