// Real GGUF timings per learning language. Not picked up by CI (`test_manual/`).
//   flutter test test_manual/manual_language_efficiency_test.dart
import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/translate/supported_languages.dart';
import 'package:ai_connect_africa/ai_core/translate/translation_pipeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _probe = 'Plants make food from sunlight.';

/// Product learning languages + one extra Latin pair + Ge'ez.
const _codes = ['sw', 'lg', 'rw', 'rn', 'ln', 'af', 'am'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler(
          (MethodCall call) async => Directory.systemTemp.path);

  test('real AfriSLM latency per language', () async {
    const candidates = [
      r'dist\models\translate-afrislm.gguf',
      r'build\windows\x64\runner\Release\models\translate-afrislm.gguf',
    ];
    final modelPath = candidates.firstWhere((p) => File(p).existsSync(),
        orElse: () => candidates.first);
    expect(File(modelPath).existsSync(), isTrue, reason: 'GGUF missing');

    stdout.writeln('Model: $modelPath '
        '(${(File(modelPath).lengthSync() / (1024 * 1024)).round()} MB)');

    final engine = LlamaCppEngineImpl();
    await engine.loadModel(modelPath);
    final pipeline = TranslationPipeline(engine, modelTag: 'live-bench');

    stdout.writeln(
        '${'lang'.padRight(6)} ${'name'.padRight(22)} '
        '${'1st ms'.padLeft(8)} ${'2nd ms'.padLeft(8)}  ok?  sample');

    final firsts = <String, int>{};
    for (final code in _codes) {
      final lang = supportedLanguages.firstWhere((l) => l.code == code);
      final t0 = DateTime.now();
      final out = await pipeline.fromEnglishDetailed(_probe, code);
      final firstMs = DateTime.now().difference(t0).inMilliseconds;
      final t1 = DateTime.now();
      final cached = await pipeline.fromEnglishDetailed(_probe, code);
      final secondMs = DateTime.now().difference(t1).inMilliseconds;
      firsts[code] = firstMs;
      final sample = out.text.replaceAll('\n', ' ');
      final clip =
          sample.length > 48 ? '${sample.substring(0, 48)}…' : sample;
      stdout.writeln(
        '${code.padRight(6)} ${lang.name.padRight(22)} '
        '${firstMs.toString().padLeft(8)} ${secondMs.toString().padLeft(8)}  '
        '${out.translated ? 'yes' : 'NO '}  $clip',
      );
      expect(cached.fromCache, isTrue, reason: '$code second call is RAM cache');
    }

    stdout.writeln('\nSame Swahili sentence as 3 clauses (cascade cost):');
    const clauses = [
      'Photosynthesis is how a plant makes food from sunlight.',
      'The leaf takes in carbon dioxide.',
      'Water travels up from the roots.',
    ];
    var clauseTotal = 0;
    for (var i = 0; i < clauses.length; i++) {
      final started = DateTime.now();
      await pipeline.fromEnglishDetailed(clauses[i], 'sw');
      final ms = DateTime.now().difference(started).inMilliseconds;
      clauseTotal += ms;
      stdout.writeln('  clause ${i + 1}: $ms ms');
    }
    stdout.writeln('  3-clause total: $clauseTotal ms');
    stdout.writeln(
        '  one-shot Swahili was ${firsts['sw']} ms — '
        'cascade/one-shot ≈ ${(clauseTotal / (firsts['sw'] ?? 1)).toStringAsFixed(2)}x');

    await engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
