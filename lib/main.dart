import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_core/model/model_runtime_policy.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One runtime per platform (model_runtime_policy.dart):
  // - Android: LiteRT-LM for the brain and the AfriSLM translator
  //   (NPU → GPU → LiteRT CPU). Each engine is created per role; the
  //   plugin init below only registers the LiteRT-LM engine.
  // - Windows / Linux: llama.cpp GGUF for both. LiteRT is never started.
  if (shouldInitializeLiteRt) {
    try {
      await FlutterGemma.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
      );
    } catch (e) {
      debugPrint('FlutterGemma init failed: $e');
    }
  }

  debugPrint(
    shouldInitializeLiteRt
        ? 'Runtime: LiteRT-LM (Android) · Qwen2.5-Coder int4 + AfriSLM int8 · NPU/GPU first'
        : 'Runtime: llama.cpp GGUF (desktop) · Qwen2.5-Coder + AfriSLM',
  );
  runApp(const ProviderScope(child: OticApp()));
}
