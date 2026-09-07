// Batch-translates the UI chrome strings into the 19 AfriSLM languages and
// writes lib/l10n/ui_strings_generated.dart.
//
// Build-time tool, not a test and not shipped. It lives under tools/ and is
// run through `flutter test` only because loading llama.cpp needs the Flutter
// bindings — the same reason test_manual/ does it:
//
//   flutter test tools/generate_ui_strings.dart
//
// Input  : tools/l10n_keys.json   (English keys, produced by the scanner)
// Output : lib/l10n/ui_strings_generated.dart
// State  : tools/.l10n_progress.json — a checkpoint after every language, so
//          a run interrupted three hours in resumes instead of restarting.
//
// Why a generated *third* table rather than appending to ui_strings.dart:
// kUiStrings and kUiStringsMore are hand-curated, and `tr()` already falls
// through them in order. Keeping machine output in its own file, consulted
// last, means a curated entry always wins and a bad batch can be deleted
// wholesale without touching reviewed text.
//
// Runtime is hours (186 keys x 19 languages on a 0.8B model, CPU). Do not run
// it while another llama.cpp process holds the model.
import 'dart:convert';
import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/translate/supported_languages.dart';
import 'package:ai_connect_africa/ai_core/translate/translation_pipeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler(
          (MethodCall call) async => Directory.systemTemp.path);

  test('generate UI string tables', () async {
    final keys = (jsonDecode(File('tools/l10n_keys.json').readAsStringSync())
            as List)
        .cast<String>();

    final env = Platform.environment;
    final candidates = [
      if (env['L10N_MODEL'] != null) env['L10N_MODEL']!,
      r'dist\models\translate-afrislm.gguf',
      r'C:\Users\esian\OneDrive\Documents\OTIC\translate-afrislm.gguf',
    ];
    final modelPath = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => candidates.first,
    );

    stdout.writeln('Model : $modelPath');
    stdout.writeln('Keys  : ${keys.length}');

    final engine = LlamaCppEngineImpl();
    await engine.loadModel(modelPath);
    final pipeline = TranslationPipeline(engine);

    // Resume from a previous run if one was interrupted.
    final progressFile = File('tools/.l10n_progress.json');
    final done = <String, Map<String, String>>{};
    if (progressFile.existsSync()) {
      final raw = jsonDecode(progressFile.readAsStringSync()) as Map;
      raw.forEach((lang, entries) {
        done[lang as String] =
            (entries as Map).map((k, v) => MapEntry(k as String, v as String));
      });
      stdout.writeln('Resuming: ${done.keys.length} languages already done');
    }

    // L10N_LANGS shards the run: CI gives each language its own job, which
    // turns a multi-hour sequential pass into one language's worth of wall
    // clock. Unset means every language, as before.
    final only = (env['L10N_LANGS'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final targets = supportedLanguages
        .where((l) => l.code != 'en')
        .where((l) => only.isEmpty || only.contains(l.code))
        .toList();
    if (targets.isEmpty) {
      throw StateError('L10N_LANGS matched no supported language: $only');
    }
    stdout.writeln('Langs : ${targets.map((l) => l.code).join(', ')}');

    for (final lang in targets) {
      if (done[lang.code]?.length == keys.length) {
        stdout.writeln('skip ${lang.code} (complete)');
        continue;
      }
      final table = done.putIfAbsent(lang.code, () => <String, String>{});
      final started = DateTime.now();
      var failed = 0;

      for (final key in keys) {
        if (table.containsKey(key)) continue;
        try {
          final out = await pipeline.fromEnglish(key, lang.code);
          final cleaned = out.trim();
          // fromEnglish returns the English original when the model produced
          // nothing usable. Storing that would bake a silent English entry
          // into the table, which is indistinguishable at runtime from a
          // missing key but can never be repaired by a later run — so drop
          // it and let tr() fall through to English on its own.
          if (cleaned.isEmpty || cleaned == key) {
            failed++;
            continue;
          }
          table[key] = cleaned;
        } catch (e) {
          failed++;
          stdout.writeln('  ! ${lang.code} "$key": $e');
        }
      }

      final secs = DateTime.now().difference(started).inSeconds;
      stdout.writeln('${lang.code}: ${table.length}/${keys.length} '
          '($failed dropped) in ${secs}s');
      progressFile.writeAsStringSync(jsonEncode(done));

      // One file per language so a sharded CI run can upload each job's
      // result and have tools/merge_ui_strings.dart stitch them together.
      final shard = Directory('tools/l10n_out')..createSync(recursive: true);
      File('${shard.path}/${lang.code}.json')
          .writeAsStringSync(jsonEncode(table));
    }

    // A sharded run only holds its own languages, so it must not overwrite the
    // full table — the merge step does that from the per-language files.
    if (only.isEmpty) {
      _writeDartTable(done, keys);
      stdout.writeln('\nWrote lib/l10n/ui_strings_generated.dart');
    } else {
      stdout.writeln('\nSharded run — wrote tools/l10n_out/*.json only');
    }
  }, timeout: const Timeout(Duration(hours: 8)));
}

void _writeDartTable(Map<String, Map<String, String>> done, List<String> keys) {
  String esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n');

  final buf = StringBuffer()
    ..writeln('// GENERATED by tools/generate_ui_strings.dart — do not edit.')
    ..writeln('//')
    ..writeln('// Machine translations of UI chrome, produced offline by')
    ..writeln('// TranslatePsy-AfriSLM. Consulted *after* the hand-curated')
    ..writeln('// kUiStrings and kUiStringsMore, so a reviewed entry always')
    ..writeln('// wins over anything here. Regenerate rather than hand-edit.')
    ..writeln('const kUiStringsGenerated = <String, Map<String, String>>{');

  for (final lang in supportedLanguages) {
    final table = done[lang.code];
    if (table == null || table.isEmpty) continue;
    buf.writeln("  '${lang.code}': {");
    for (final key in keys) {
      final value = table[key];
      if (value == null) continue;
      buf.writeln("    '${esc(key)}': '${esc(value)}',");
    }
    buf.writeln('  },');
  }
  buf.writeln('};');

  File('lib/l10n/ui_strings_generated.dart').writeAsStringSync(buf.toString());
}
