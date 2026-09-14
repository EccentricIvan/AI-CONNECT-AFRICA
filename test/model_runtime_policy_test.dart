import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/model/model_runtime_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android: LiteRT chat + LiteRT coder', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(useLiteRtChatBrain, isTrue);
    expect(useGgufChatBrain, isFalse);
    expect(useLiteRtCoderRuntime, isTrue);
    expect(shouldInitializeLiteRt, isTrue);
    expect(
      ModelManager.chatFileNamesForPlatform().first,
      ModelManager.chatModelFileName,
    );
    expect(
      isAllowedChatBrainPath(ModelManager.bundledChatModelPath),
      isTrue,
    );
    expect(
      isAllowedChatBrainPath(r'/models/qwen_brain_0.6b.Q4_K_M.gguf'),
      isTrue,
    );
    expect(
      isAllowedCoderPath(r'/models/qwen_coder_1.5b.litertlm'),
      isTrue,
    );
  });

  test('Windows: GGUF chat + GGUF CPU coder', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(useLiteRtChatBrain, isFalse);
    expect(useGgufChatBrain, isTrue);
    expect(useLiteRtCoderRuntime, isFalse);
    expect(shouldInitializeLiteRt, isFalse);
    expect(
      ModelManager.chatFileNamesForPlatform().first,
      ModelManager.canonicalChatGgufFileName,
    );
    expect(
      isAllowedCoderPath(r'C:\models\qwen_coder_1.5b.Q4_K_M.gguf'),
      isTrue,
    );
  });
}
