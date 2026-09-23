import 'package:ai_connect_africa/ai_core/model/model_runtime_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android: GGUF brain, or a LiteRT export when one is installed', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(useLiteRtRuntime, isTrue);
    expect(shouldInitializeLiteRt, isTrue);
    expect(isAllowedBrainPath('/models/qwen2.5-coder-1.5b-instruct.gguf'),
        isTrue);
    expect(isAllowedBrainPath('/models/qwen_coder_1.5b.litertlm'), isTrue);
    expect(isLiteRtModelPath('/models/qwen_coder_1.5b.litertlm'), isTrue);
    expect(isLiteRtModelPath('/models/qwen2.5-coder-1.5b-instruct.gguf'),
        isFalse);
  });

  test('Windows: GGUF only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(useLiteRtRuntime, isFalse);
    expect(shouldInitializeLiteRt, isFalse);
    expect(isAllowedBrainPath(r'C:\models\qwen2.5-coder-1.5b-instruct.gguf'),
        isTrue);
    expect(isAllowedBrainPath(r'C:\models\qwen_coder_1.5b.litertlm'),
        isFalse);
  });
}
