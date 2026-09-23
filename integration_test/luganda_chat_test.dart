import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:ai_connect_africa/ai_core/science/science_text.dart';
import 'package:ai_connect_africa/ai_core/tutor/school_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

String? _ggufPath() {
  final names = AfriSlmModelManager.allFileNames;
  const roots = [
    'assets/models',
    'dist/models',
  ];
  for (final root in roots) {
    for (final name in names) {
      final f = File('$root/$name');
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AfriSLM GGUF loads and streams native Luganda', (tester) async {
    final path = _ggufPath();
    if (path == null) {
      return;
    }
    final engine = LlamaCppEngineImpl();
    await engine.loadModel(path);
    addTearDown(engine.dispose);

    final buf = StringBuffer();
    final out = await engine.generate(
      prompt: 'Nnyonnyola photosynthesis mu Luganda, emirimu 2.',
      systemPrompt: 'Reply in Luganda. Keep formulas in \$...\$ if any.',
      maxTokens: 64,
      temperature: 0,
      onToken: (t) => buf.write(t),
    );
    expect(out.trim(), isNotEmpty);
    expect(repairUnclosedMathDelimiters(buf.toString()), isNotEmpty);
  });

  testWidgets('math-operator queries are not curriculum RAG', (tester) async {
    expect(queryLooksLikeMath('Shaka agaciro ka 4x - 15 = 12x'), isTrue);
    expect(queryLooksLikeMath('Nnyonnyola photosynthesis.'), isFalse);
  });
}
