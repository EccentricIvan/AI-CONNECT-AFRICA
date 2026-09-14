import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../ai_core/inference/litert_lm_engine.dart';
import '../ai_core/tutor/tutor_contract.dart';

/// Which LiteRT configuration currently owns FlutterGemma's single active slot.
enum ActiveModelMode {
  none,
  chatBrain,
  appCoder,
}

/// Android-only dynamic LiteRT swapper.
///
/// FlutterGemma exposes one active InferenceModel at a time. Switching from
/// the 0.6B chat brain to the 1.5B coder (or back) without an explicit unload
/// leaves stale KV / mmap pressure and feels like "token friction".
///
/// Windows / Linux **bypass** this entirely — llama.cpp keeps separate GGUF
/// engines and does not share a single active-model slot.
class AiModelManager {
  AiModelManager._();
  static final AiModelManager instance = AiModelManager._();

  ActiveModelMode _mode = ActiveModelMode.none;
  LiteRtLmEngineImpl? _chatEngine;
  LiteRtLmEngineImpl? _coderEngine;
  String? _chatPath;
  String? _coderPath;

  Future<void>? _inflight;

  ActiveModelMode get activeMode => _mode;

  LiteRtLmEngineImpl? get chatEngine => _chatEngine;
  LiteRtLmEngineImpl? get coderEngine => _coderEngine;

  /// Real Android OS only — not [defaultTargetPlatform] (unit tests often fake Android).
  bool get isAndroidLiteRtHost {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Bind the chat LiteRT engine created by DualModelRuntime.
  void registerChatBrain({
    required LiteRtLmEngineImpl engine,
    required String path,
  }) {
    _chatEngine = engine;
    _chatPath = path;
    if (_mode == ActiveModelMode.none) {
      _mode = ActiveModelMode.chatBrain;
    }
    debugPrint('AiModelManager: registered chatBrain @ $path');
  }

  /// Bind the coder LiteRT engine (path may be registered before first load).
  void registerAppCoder({
    required LiteRtLmEngineImpl engine,
    required String path,
  }) {
    _coderEngine = engine;
    _coderPath = path;
    debugPrint('AiModelManager: registered appCoder @ $path');
  }

  /// Register coder path before the engine exists (lazy construct on prepare).
  void registerAppCoderPath(String path) {
    _coderPath = path;
    _coderEngine ??= LiteRtLmEngineImpl(roleLabel: 'Qwen 1.5B coder');
    debugPrint('AiModelManager: registered appCoder path @ $path');
  }

  /// Atomic prepare: no-op if already active; otherwise unload → settle → load.
  Future<void> prepareModelForMode(ActiveModelMode targetMode) async {
    if (!isAndroidLiteRtHost || targetMode == ActiveModelMode.none) {
      return;
    }

    while (_inflight != null) {
      try {
        await _inflight;
      } catch (_) {}
    }
    final op = _prepareLocked(targetMode);
    _inflight = op;
    try {
      await op;
    } finally {
      if (identical(_inflight, op)) _inflight = null;
    }
  }

  Future<void> _prepareLocked(ActiveModelMode targetMode) async {
    if (_mode == targetMode) {
      await _ensureMapped(targetMode);
      return;
    }

    debugPrint('AiModelManager: swap ${_mode.name} → ${targetMode.name}');

    if (_mode == ActiveModelMode.chatBrain) {
      await _unloadEngine(_chatEngine, label: 'chatBrain');
    } else if (_mode == ActiveModelMode.appCoder) {
      await _unloadEngine(_coderEngine, label: 'appCoder');
    }
    _mode = ActiveModelMode.none;

    // Dart has no public gc() in production builds. Clear native handles
    // above, then settle so the OS can reclaim mmap pages before reload.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await _ensureMapped(targetMode);
    _mode = targetMode;
    debugPrint('AiModelManager: active=${_mode.name}');
  }

  Future<void> _ensureMapped(ActiveModelMode targetMode) async {
    switch (targetMode) {
      case ActiveModelMode.none:
        return;
      case ActiveModelMode.chatBrain:
        final path = _chatPath;
        final engine = _chatEngine;
        if (path == null || engine == null) {
          debugPrint('AiModelManager: chatBrain not registered — skip load');
          return;
        }
        await engine.ensureLoaded(path);
        await engine.pinSystemPrompt(kTutorContract);
        return;
      case ActiveModelMode.appCoder:
        final path = _coderPath;
        if (path == null) {
          debugPrint('AiModelManager: appCoder path missing — skip load');
          return;
        }
        final engine =
            _coderEngine ?? LiteRtLmEngineImpl(roleLabel: 'Qwen 1.5B coder');
        _coderEngine = engine;
        await engine.ensureLoaded(path);
        await engine.pinSystemPrompt(
          '$kProgrammingTutorContract\n'
          'Reply with code only when building sites/apps.',
        );
        return;
    }
  }

  Future<void> _unloadEngine(
    LiteRtLmEngineImpl? engine, {
    required String label,
  }) async {
    if (engine == null) return;
    try {
      await engine.dispose();
      debugPrint('AiModelManager: unloaded $label');
    } catch (e) {
      debugPrint('AiModelManager: unload $label failed: $e');
    }
  }

  /// Clears mode tracking (tests / full runtime teardown).
  Future<void> resetForTests() async {
    await _unloadEngine(_chatEngine, label: 'chatBrain');
    await _unloadEngine(_coderEngine, label: 'appCoder');
    _mode = ActiveModelMode.none;
    _chatEngine = null;
    _coderEngine = null;
    _chatPath = null;
    _coderPath = null;
  }
}

/// Fire-and-forget screen hook — Android only.
void scheduleLiteRtMode(ActiveModelMode mode) {
  if (kIsWeb) return;
  try {
    if (!Platform.isAndroid) return;
  } catch (_) {
    return;
  }
  unawaited(AiModelManager.instance.prepareModelForMode(mode));
}
