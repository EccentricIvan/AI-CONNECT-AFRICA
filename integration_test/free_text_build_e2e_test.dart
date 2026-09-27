import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/runtime_config.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_build_coder.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_type_classifier.dart';
import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:ai_connect_africa/features/site_builder/site_template_classifier.dart';
import 'package:ai_connect_africa/shared/coding/interactive_html.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The free-text build path with the real on-device coder: a learner's
/// description in, a page out. Set OTIC_E2E_OUT to keep the pages.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const apps = [
    'an app for my class to track who has paid school fees this term',
    'a chicken farm app to count eggs every day and plan feeding',
  ];
  const sites = [
    'a website for our football club with fixtures, players and a contact form',
  ];

  testWidgets('coder writes apps and sites from a description', (tester) async {
    final info = await ModelManager().checkModel();
    expect(info.isReady && info.path != null, isTrue,
        reason: 'Coder GGUF missing: ${info.status} ${info.path}');
    final coder = LlamaCppEngineImpl(
      schedulerLane: EngineLane.program,
      backendLabel: 'llama.cpp · Qwen2.5-Coder 1.5B',
      appendNoThink: false,
    );
    await coder.loadModel(info.path!);
    addTearDown(coder.dispose);
    final outDir = Platform.environment['OTIC_E2E_OUT'];

    var n = 0;
    for (final description in apps) {
      final type = classifyAppType(description);
      final watch = Stopwatch()..start();
      final html = await generateAppHtmlWithCoder(
        engine: coder,
        maxTokens: kAppFreeTextBuildMaxTokens,
        intent: AppBuildIntent(
          appTypeId: type.id,
          appTypeName: type.name,
          themeId: '1',
          themeName: 'Ocean Blue',
          themePrimary: '#2563eb',
          answers: const {},
          features: const [],
          description: description,
        ),
      );
      await coder.resetSession();
      _report('APP', description, type.id, html, watch, outDir, 'app${++n}');
      expect(html, isNotNull, reason: description);
      expect(hasVisibleContent(html!), isTrue, reason: description);
    }

    for (final description in sites) {
      final template = classifySiteTemplate(description);
      final watch = Stopwatch()..start();
      final html = await generateSiteHtmlWithCoder(
        engine: coder,
        intent: SiteBuildIntent(
          templateId: template.id,
          templateName: template.name,
          themeName: 'Default',
          themePrimary: null,
          answers: const {},
          content: const {},
          description: description,
        ),
      );
      await coder.resetSession();
      _report('SITE', description, template.id, html, watch, outDir, 'site${++n}');
      expect(html, isNotNull, reason: description);
      expect(hasVisibleContent(html!), isTrue, reason: description);
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

void _report(String kind, String description, String typeId, String? html,
    Stopwatch watch, String? outDir, String name) {
  final visible = html != null && hasVisibleContent(html);
  debugPrint('E2E $kind [$typeId] ${watch.elapsed.inSeconds}s '
      'chars=${html?.length ?? 0} visible=$visible '
      'title=${html == null ? null : extractPageTitle(html)} :: $description');
  if (outDir != null && html != null) {
    File('$outDir/$name.html').writeAsStringSync(html);
  }
}
