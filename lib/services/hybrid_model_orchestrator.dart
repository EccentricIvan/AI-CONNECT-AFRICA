import '../ai_core/inference/engine_scheduler.dart';

/// Serializes chat / coder / translator so only one model runs native
/// decode at a time (memory safety on low-RAM devices).
class HybridModelOrchestrator {
  HybridModelOrchestrator._();
  static final HybridModelOrchestrator instance = HybridModelOrchestrator._();

  Future<T> runExclusive<T>(Future<T> Function() job) {
    return EngineScheduler.instance.exclusive(
      job,
      lane: EngineLane.hybrid,
    );
  }
}
