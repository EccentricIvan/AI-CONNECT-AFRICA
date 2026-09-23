import 'package:ai_connect_africa/ai_core/model/dual_gguf_plan.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const missing = ModelInfo(status: ModelStatus.notInstalled);
  const coder = ModelInfo(
    status: ModelStatus.ready,
    path: r'C:\models\qwen2.5-coder-1.5b-instruct.gguf',
  );
  const afrislm = ModelInfo(
    status: ModelStatus.ready,
    path: r'C:\models\afrislm-0.8b-q4_k_m.gguf',
  );

  test('AfriSLM alone does not become the tutor brain', () {
    final plan = planDualGgufs(missing, afrislm);
    expect(plan.canTutor, isFalse);
    expect(plan.canTranslate, isTrue);
    expect(plan.brainPath, isNull);
    expect(plan.afrislmPath, afrislm.path);
  });

  test('the coder alone tutors in English with no translator', () {
    final plan = planDualGgufs(coder, missing);
    expect(plan.canTutor, isTrue);
    expect(plan.canTranslate, isFalse);
    expect(plan.brainPath, coder.path);
  });

  test('both files keep separate roles', () {
    final plan = planDualGgufs(coder, afrislm);
    expect(plan.brainPath, coder.path);
    expect(plan.afrislmPath, afrislm.path);
    expect(plan.sameFile, isFalse);
  });

  test('the brain is the coder on every platform; no 0.6B names remain', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      final names = ModelManager.brainFileNamesForPlatform();
      expect(names, contains(ModelManager.brainGgufFileName));
      expect(names.where((n) => n.contains('0.6b') || n.contains('0.6B')),
          isEmpty);
      expect(names.where((n) => n == 'chat-model.litertlm'), isEmpty);
    }
    debugDefaultTargetPlatformOverride = null;
    expect(ModelManager.ggufBrainFileNames.first,
        'qwen2.5-coder-1.5b-instruct.gguf');
  });
}
