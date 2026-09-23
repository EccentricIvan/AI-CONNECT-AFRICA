import 'model_manager.dart';

/// Assigns the two on-disk models to their roles.
///
/// The brain (Qwen2.5-Coder-1.5B) does all reasoning and answering; AfriSLM
/// only translates. AfriSLM is never used as the brain.
class DualGgufPlan {
  const DualGgufPlan({this.brainPath, this.afrislmPath});

  final String? brainPath;
  final String? afrislmPath;

  bool get canTutor => brainPath != null && brainPath!.isNotEmpty;
  bool get canTranslate => afrislmPath != null && afrislmPath!.isNotEmpty;

  /// True only if both roles pointed at the same file (mis-install).
  bool get sameFile => canTutor && canTranslate && brainPath == afrislmPath;
}

DualGgufPlan planDualGgufs(ModelInfo brain, ModelInfo translate) {
  return DualGgufPlan(
    brainPath: brain.isReady ? brain.path : null,
    afrislmPath: translate.isReady ? translate.path : null,
  );
}
