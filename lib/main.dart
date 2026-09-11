import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Qwen 0.6B GGUF is the general brain (llama.cpp). 1.5B Coder is
  // programming. AfriSLM translates. LiteRT stays registered as fallback.
  if (!kIsWeb) {
    try {
      await FlutterGemma.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
      );
    } catch (e) {
      debugPrint('FlutterGemma init failed: $e');
    }
  }

  debugPrint('Qwen 0.6B brain + Qwen 1.5B coder + AfriSLM translator');
  runApp(const ProviderScope(child: OticApp()));
}
