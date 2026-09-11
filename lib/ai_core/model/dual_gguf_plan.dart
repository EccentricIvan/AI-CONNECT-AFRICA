import 'model_manager.dart';

/// Qwen 0.6B is the general tutor brain. Qwen 1.5B Coder is programming.
/// AfriSLM is the translator. AfriSLM is never used as a brain.
class DualGgufPlan {
  const DualGgufPlan({
    this.qwenPath,
    this.afrislmPath,
    this.programmingPath,
  });

  final String? qwenPath;
  final String? afrislmPath;
  final String? programmingPath;

  bool get canTutor => qwenPath != null && qwenPath!.isNotEmpty;
  bool get canTranslate => afrislmPath != null && afrislmPath!.isNotEmpty;
  bool get canProgram =>
      programmingPath != null && programmingPath!.isNotEmpty;

  /// True only if both roles pointed at the same file (mis-install).
  bool get sameFile =>
      canTutor && canTranslate && qwenPath == afrislmPath;
}

/// Assigns on-disk files to roles. AfriSLM is never used as the brain.
DualGgufPlan planDualGgufs(
  ModelInfo qwen,
  ModelInfo translate, [
  ModelInfo programming = const ModelInfo(status: ModelStatus.notInstalled),
]) {
  String? programmingPath;
  if (programming.isReady &&
      programming.path != null &&
      programming.path != qwen.path &&
      programming.path != translate.path) {
    programmingPath = programming.path;
  }
  return DualGgufPlan(
    qwenPath: qwen.isReady ? qwen.path : null,
    afrislmPath: translate.isReady ? translate.path : null,
    programmingPath: programmingPath,
  );
}
