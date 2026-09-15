import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/programming_model_manager.dart';
import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live e2e: the 1.5B coder builds a real website, then we check that the
/// preview pane would paint exactly the code the editor shows — the way
/// Chrome renders a file and nothing else.
///
/// Every existing preview test feeds *hand-written* templates through the
/// repair layer. This is the untested case: genuine model output, with
/// whatever truncation and stray fences a 1.5B on CPU actually emits.
///
/// ```powershell
/// flutter test test_manual/manual_site_preview_fidelity_test.dart --name live
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler((_) async => Directory.systemTemp.path);

  final outDir = Directory(
    Platform.environment['OTIC_E2E_OUT'] ?? Directory.systemTemp.path,
  );

  test(
    'live coder output reaches the preview byte-identical',
    () async {
      outDir.createSync(recursive: true);

      final info = await ProgrammingModelManager().checkModel();
      expect(
        info.isReady && info.path != null,
        isTrue,
        reason: 'Coder GGUF missing: ${info.status} ${info.path}',
      );
      stdout.writeln('LOAD CODER ${info.path} (${info.sizeBytes} bytes)');

      final engine = LlamaCppEngineImpl(
        schedulerLane: EngineLane.program,
        backendLabel: 'llama.cpp · Qwen 1.5B Coder',
      );
      await engine.loadModel(info.path!);
      addTearDown(engine.dispose);
      stdout.writeln('LOADED CODER');

      final intent = SiteBuildIntent(
        templateId: 'bakery',
        templateName: 'Bakery / Restaurant',
        themeName: 'Ocean Blue',
        themePrimary: '#2563eb',
        answers: {
          'business_name': 'Kampala Crust Bakery',
          'phone': '+256 700 111 222',
          'address': 'Plot 9, Kampala Road',
        },
        content: {
          'tagline': 'Fresh bread every morning',
          'description': 'A student bakery site for local customers.',
          'about': 'We bake with local flour and love.',
        },
      );

      // Keep the raw stream so we can tell a model problem (truncated output)
      // apart from a pipeline problem (the preview altering the code).
      final raw = StringBuffer();
      stdout.writeln('BUILD WEBSITE…');
      final started = DateTime.now();
      final editorHtml = await generateSiteHtmlWithCoder(
        engine: engine,
        intent: intent,
        onToken: (cumulative) {
          raw
            ..clear()
            ..write(cumulative);
        },
      );
      final elapsed = DateTime.now().difference(started);
      stdout.writeln('BUILD DONE in ${elapsed.inSeconds}s');

      File('${outDir.path}/raw_model_stream.txt')
          .writeAsStringSync(raw.toString());
      expect(editorHtml, isNotNull, reason: 'coder returned no HTML');

      // What the student sees in the editor on the left.
      File('${outDir.path}/editor.html').writeAsStringSync(editorHtml!);
      stdout.writeln('EDITOR HTML: ${editorHtml.length} chars');

      // What the preview pane hands to the browser engine on the right.
      final previewHtml = prepareHtmlForPreview(editorHtml);
      File('${outDir.path}/preview.html').writeAsStringSync(previewHtml);
      stdout.writeln('PREVIEW HTML: ${previewHtml.length} chars');

      // 1. THE fidelity check: the pane paints the editor's bytes, unchanged.
      expect(
        previewHtml,
        editorHtml,
        reason: 'the preview is not showing the code in the editor',
      );

      // 2. Nothing executable was injected. Closing an unclosed tag is what a
      //    browser parser does anyway; adding JavaScript is not.
      expect(
        previewHtml,
        isNot(contains('}catch(e){}')),
        reason: 'the repair layer injected JS the student did not write',
      );

      // 3. No canned demo content.
      for (final invented in const [
        'OTIC_INTERACTIVE_RUNTIME',
        'Interactive offline preview',
        'Checkout calculator',
        'Quick quiz',
        'Theme lab',
      ]) {
        expect(previewHtml, isNot(contains(invented)));
      }

      // 4. The model honoured "no CDN" — offline for real, not just in prompt.
      final networkRef = RegExp(
        r'''(src|href)\s*=\s*['"]?\s*(https?:)?//|@import\s+url\(\s*['"]?\s*(https?:)?//|cdn\.|fonts\.googleapis''',
        caseSensitive: false,
      );
      final leak = networkRef.firstMatch(previewHtml);
      expect(
        leak,
        isNull,
        reason: 'generated site needs the network: "${leak?.group(0)}"',
      );

      // 5. It is a real, complete document the browser can parse.
      expect(previewHtml, contains(RegExp('<!DOCTYPE html>', caseSensitive: false)));
      expect(previewHtml.toLowerCase(), contains('</html>'));
      expect(previewHtml.toLowerCase(), contains('</body>'));

      // 6. The student's own details, not invented ones.
      expect(
        previewHtml.contains('Kampala Crust') || previewHtml.contains('Kampala'),
        isTrue,
        reason: 'the site dropped the student details',
      );

      // 7. The exact file the Windows pane loads into WebView2.
      final served = await writeTempPreviewFile(previewHtml);
      final servedBytes = File(served.path).readAsStringSync();
      File('${outDir.path}/served_to_webview2.html')
          .writeAsStringSync(servedBytes);
      expect(
        servedBytes,
        editorHtml,
        reason: 'the file handed to WebView2 differs from the editor',
      );
      stdout.writeln('SERVED FILE: ${served.path}');
      stdout.writeln('ALL PREVIEW FIDELITY CHECKS PASSED');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
