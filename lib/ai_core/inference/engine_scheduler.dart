import 'dart:async';

/// Per-engine native decode lanes.
///
/// Qwen (reason) and AfriSLM (translate) must not share a lane: outbound
/// translation has to run while Qwen is still emitting English tokens.
/// Two [LlamaCppEngineImpl] instances plus two lanes is the overlap.
///
/// A single shared GGUF uses [reason] for both hops and stays sequential.
class EngineLane {
  static const reason = 'reason';
  static const program = 'program';
  static const translate = 'translate';

  /// Global sequential lane — chat, coder, and translator must not spike
  /// RAM concurrently on 4 GB phones / dual-core school PCs.
  static const hybrid = 'hybrid';
}

/// Serializes jobs that share a native runtime.
class EngineScheduler {
  EngineScheduler._();
  static final EngineScheduler instance = EngineScheduler._();

  final Map<String, Future<void>> _tails = {};

  Future<T> exclusive<T>(
    Future<T> Function() job, {
    String lane = EngineLane.reason,
  }) async {
    final previous = _tails[lane] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[lane] = done.future;
    try {
      try {
        await previous;
      } catch (_) {}
      return await job();
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }
}
