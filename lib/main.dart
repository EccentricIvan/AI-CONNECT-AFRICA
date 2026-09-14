import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_core/model/model_runtime_policy.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hybrid stack:
  // - Chat brain: llama.cpp GGUF on Android + Windows
  // - Coder: LiteRT on Android (needs FlutterGemma), GGUF CPU on Windows
  // - Translator: isolated via AiEngineService (AfriSLM today)
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
    'Low-latency hybrid: '
    '${shouldInitializeLiteRt ? 'Android LiteRT chat+coder (NNAPI/GPU)' : 'Desktop GGUF chat+coder (AVX2 CPU×2)'} · '
    'isolated translator · pinned KV',
  );
  runApp(const ProviderScope(child: OticApp()));
}
