import 'package:ai_connect_africa/ai_core/model/dual_gguf_plan.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const missing = ModelInfo(status: ModelStatus.notInstalled);
  const qwen = ModelInfo(
    status: ModelStatus.ready,
    path: r'C:\models\qwen-0.6b-instruct.gguf',
  );
  const afrislm = ModelInfo(
    status: ModelStatus.ready,
    path: r'C:\models\afrislm-0.8b-q4_k_m.gguf',
  );

  test('AfriSLM alone does not become the tutor brain', () {
    final plan = planDualGgufs(missing, afrislm);
    expect(plan.canTutor, isFalse);
    expect(plan.canTranslate, isTrue);
    expect(plan.qwenPath, isNull);
    expect(plan.afrislmPath, afrislm.path);
  });

  test('Qwen alone tutors in English with no translator', () {
    final plan = planDualGgufs(qwen, missing);
    expect(plan.canTutor, isTrue);
    expect(plan.canTranslate, isFalse);
    expect(plan.qwenPath, qwen.path);
  });

  test('both files keep separate roles', () {
    final plan = planDualGgufs(qwen, afrislm);
    expect(plan.canTutor, isTrue);
    expect(plan.canTranslate, isTrue);
    expect(plan.qwenPath, qwen.path);
    expect(plan.afrislmPath, afrislm.path);
    expect(plan.sameFile, isFalse);
    expect(plan.canProgram, isFalse);
  });

  test('1.5B coder is a third role, never AfriSLM or 0.6B', () {
    const coder = ModelInfo(
      status: ModelStatus.ready,
      path: r'C:\models\qwen2.5-coder-1.5b-instruct.gguf',
    );
    final plan = planDualGgufs(qwen, afrislm, coder);
    expect(plan.canProgram, isTrue);
    expect(plan.programmingPath, coder.path);
    expect(plan.qwenPath, qwen.path);
    expect(plan.afrislmPath, afrislm.path);
  });

  test('Qwen GGUF is discovered before the LiteRT fallback', () {
    expect(
      ModelManager.alternateChatFileNames.first,
      ModelManager.qwenGgufFileName,
    );
    expect(
      ModelManager.alternateChatFileNames.last,
      ModelManager.chatModelFileName,
    );
  });
}
