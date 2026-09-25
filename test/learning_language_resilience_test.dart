import 'package:ai_connect_africa/ai_core/model/bundled_model_bootstrap.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/chat_languages.dart';
import 'package:ai_connect_africa/ai_core/translate/supported_languages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveLearningLanguage prefers override, then profile, then prefs', () {
    expect(
      resolveLearningLanguage(override: 'sw', persisted: 'lg', studentLanguage: 'en'),
      'sw',
    );
    expect(
      resolveLearningLanguage(persisted: 'lg', studentLanguage: 'yo'),
      'yo',
    );
    expect(resolveLearningLanguage(persisted: 'lg'), 'lg');
    expect(resolveLearningLanguage(studentLanguage: 'yo'), 'yo');
    expect(resolveLearningLanguage(), 'en');
    expect(resolveLearningLanguage(persisted: 'fr'), 'en');
  });

  test('coerceChatLanguage keeps every AfriSLM language', () {
    expect(coerceChatLanguage('lg'), 'lg');
    expect(coerceChatLanguage('yo'), 'yo');
    expect(coerceChatLanguage('zu'), 'zu');
    expect(coerceChatLanguage('rn'), 'rw');
    expect(coerceChatLanguage('fr'), 'en');
  });

  test("fat APK bootstrap looks for this platform's translator files", () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(
      BundledModelBootstrap.translateAssetCandidates,
      contains('models/${AfriSlmModelManager.modelFileName}'),
    );
    expect(
      BundledModelBootstrap.translateAssetCandidates,
      contains('models/translate-afrislm.gguf'),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      BundledModelBootstrap.translateAssetCandidates,
      containsAll(['models/afrislm-0.8b_int8.litertlm', 'models/afrislm-0.8b_int4.litertlm']),
    );
  });

  test('AfriSLM prompt names stay on the model card', () {
    expect(chatTranslatePromptName('lg'), 'Luganda');
    expect(languagePromptName('ny'), 'Nyanja');
    expect(isSupportedLearningLanguage('sw'), isTrue);
    expect(isSupportedLearningLanguage('fr'), isFalse);
  });
}
