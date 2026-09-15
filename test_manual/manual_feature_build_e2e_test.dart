import 'dart:io';

import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/model/programming_model_manager.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_build_coder.dart';
import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live e2e: 1.5B coder builds a website and an app from recorded features.
///
/// One test loads the coder once (loading a second GGUF in-process can crash).
///
/// ```powershell
/// flutter test test_manual/manual_feature_build_e2e_test.dart --name "live"
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler((_) async => Directory.systemTemp.path);

  test(
    'live coder builds website and app from feature selection',
    () async {
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

      final siteIntent = SiteBuildIntent(
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

      stdout.writeln('BUILD WEBSITE…');
      final siteHtml = await generateSiteHtmlWithCoder(
        engine: engine,
        intent: siteIntent,
      );
      stdout.writeln(
        'SITE HTML: ${siteHtml == null ? 'null' : '${siteHtml.length} chars'}',
      );
      if (siteHtml != null) {
        stdout.writeln(siteHtml.substring(0, siteHtml.length.clamp(0, 400)));
      }

      expect(siteHtml, isNotNull, reason: 'Website build returned no HTML');
      expect(siteHtml!, contains(RegExp(r'<!DOCTYPE html>', caseSensitive: false)));
      expect(siteHtml.toLowerCase(), contains('<html'));
      expect(siteHtml.toLowerCase(), contains('<body'));
      // Prefer student name; accept partial decode from small models.
      final siteMentionsBusiness = siteHtml.contains('Kampala Crust') ||
          siteHtml.toLowerCase().contains('bakery');
      expect(siteMentionsBusiness, isTrue,
          reason: 'Website HTML missing bakery identity');

      final appIntent = AppBuildIntent(
        appTypeId: 'quiz',
        appTypeName: 'Quiz Game',
        themeId: 'royal',
        themeName: 'Royal Purple',
        themePrimary: '#7c3aed',
        answers: {
          'app_name': 'BrainBoost Quiz',
          'purpose': 'Practice math before exams',
        },
        features: ['Question screen', 'Score tracker'],
      );

      stdout.writeln('BUILD APP…');
      final appHtml = await generateAppHtmlWithCoder(
        engine: engine,
        intent: appIntent,
      );
      stdout.writeln(
        'APP HTML: ${appHtml == null ? 'null' : '${appHtml.length} chars'}',
      );
      if (appHtml != null) {
        stdout.writeln(appHtml.substring(0, appHtml.length.clamp(0, 400)));
      }

      expect(appHtml, isNotNull, reason: 'App build returned no HTML');
      expect(appHtml!, contains(RegExp(r'<!DOCTYPE html>', caseSensitive: false)));
      expect(appHtml.toLowerCase(), contains('<html'));
      expect(appHtml.toLowerCase(), contains('<body'));
      final appMentions = appHtml.contains('BrainBoost') ||
          appHtml.toLowerCase().contains('quiz') ||
          appHtml.toLowerCase().contains('score');
      expect(appMentions, isTrue, reason: 'App HTML missing quiz identity');

      stdout.writeln('E2E BUILD OK');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
