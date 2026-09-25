import 'package:ai_connect_africa/ai_core/model/device_tier.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/model/model_runtime_policy.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One runtime per platform, never mixed: Android is LiteRT-LM only,
/// desktop is llama.cpp only. A file in the other platform's format must
/// not count as installed, or the wrong runtime would be asked to load it.
void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DeviceTier.overrideForTesting(null);
  });

  test('Android: LiteRT-LM only — a GGUF is not a usable model', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(androidUsesLiteRt, isTrue);
    expect(desktopUsesLlamaCpp, isFalse);
    expect(shouldInitializeLiteRt, isTrue);
    expect(platformModelExtension, '.litertlm');
    expect(isAllowedBrainPath('/models/qwen2.5-coder-1.5b-instruct_int4.litertlm'), isTrue);
    expect(isAllowedBrainPath('/models/qwen2.5-coder-1.5b-instruct.gguf'), isFalse);
    expect(isAllowedModelPath('/models/afrislm-0.8b-q4_k_m.gguf'), isFalse);
    expect(ModelManager.brainFileName, ModelManager.brainLiteRtFileName);
    expect(ModelManager.brainFileNamesForPlatform().every(isLiteRtModelPath), isTrue);
    expect(AfriSlmModelManager.modelFileName, 'afrislm-0.8b_int8.litertlm');
    expect(AfriSlmModelManager.allFileNames.every(isLiteRtModelPath), isTrue);
  });

  test('Windows: llama.cpp GGUF only — a .litertlm is not a usable model', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(androidUsesLiteRt, isFalse);
    expect(desktopUsesLlamaCpp, isTrue);
    expect(shouldInitializeLiteRt, isFalse);
    expect(platformModelExtension, '.gguf');
    expect(isAllowedBrainPath(r'C:\models\qwen2.5-coder-1.5b-instruct.gguf'), isTrue);
    expect(isAllowedBrainPath(r'C:\models\qwen2.5-coder-1.5b-instruct_int4.litertlm'), isFalse);
    expect(ModelManager.brainFileName, ModelManager.brainGgufFileName);
    expect(ModelManager.brainFileNamesForPlatform().every(isGgufModelPath), isTrue);
    expect(AfriSlmModelManager.allFileNames.every(isGgufModelPath), isTrue);
  });

  group('DeviceTier', () {
    test('a 4 GB phone is low-memory, an 8 GB one is not', () {
      expect(DeviceTier.fromMeminfo('MemTotal:        3812344 kB\nMemFree: 1 kB').isLowMemory, isTrue);
      expect(DeviceTier.fromMeminfo('MemTotal:        7812344 kB').isLowMemory, isFalse);
    });

    test('unknown memory is treated as low (a little slower beats a crash)', () {
      expect(DeviceTier.fromMeminfo('garbage').isLowMemory, isTrue);
    });

    test('every phone downloads the int8 translator (int4 failed its quality gate)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final mem in ['MemTotal: 3812344 kB', 'MemTotal: 7812344 kB']) {
        DeviceTier.overrideForTesting(DeviceTier.fromMeminfo(mem));
        expect(AfriSlmModelManager.liteRtPreferredFileName, 'afrislm-0.8b_int8.litertlm');
      }
    });
  });
}
