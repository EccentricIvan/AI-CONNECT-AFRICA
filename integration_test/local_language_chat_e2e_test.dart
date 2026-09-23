import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/litert_lm_engine.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/chat_languages.dart';
import 'package:ai_connect_africa/ai_core/translate/translation_pipeline.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/services/chat_inference_pipeline.dart';
import 'package:ai_connect_africa/services/qwen_reasoning_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The brain (Qwen2.5-Coder-1.5B) tutoring, with AfriSLM for local languages.
///
/// One GGUF at a time: reason first, unload, then AfriSLM. Loading a second
/// llama.cpp model while another is (or was) mapped has crashed this harness.

const _localCodes = ['lg', 'sw', 'rw', 'so', 'ln'];

Future<InferenceEngine> _loadChatBrain(String path) async {
  debugPrint('LOAD CHAT $path');
  if (path.toLowerCase().endsWith('.gguf')) {
    final engine = LlamaCppEngineImpl(
      schedulerLane: EngineLane.reason,
      backendLabel: 'llama.cpp · Qwen2.5-Coder 1.5B',
      appendNoThink: false,
    );
    await engine.loadModel(path);
    debugPrint('LOADED CHAT');
    return engine;
  }
  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
  );
  final engine = LiteRtLmEngineImpl();
  await engine.loadModel(path);
  debugPrint('LOADED CHAT LiteRT');
  return engine;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Coder brain tutoring, then AfriSLM for every local language',
    (tester) async {
      expect(
        kPrimaryChatLanguages.where((c) => c != 'en').toList(),
        _localCodes,
      );

      final chatInfo = await ModelManager().checkModel();
      final afrislmInfo = await AfriSlmModelManager().checkModel();
      expect(chatInfo.isReady && chatInfo.path != null, isTrue,
          reason: 'Chat GGUF missing: ${chatInfo.status} ${chatInfo.path}');
      expect(afrislmInfo.isReady && afrislmInfo.path != null, isTrue,
          reason: 'AfriSLM missing: ${afrislmInfo.status} ${afrislmInfo.path}');
      expect(chatInfo.path!.toLowerCase().contains('afrislm'), isFalse);
      debugPrint('CHAT ${chatInfo.path}');
      debugPrint('AFRISLM ${afrislmInfo.path}');

      late final String englishReply;
      final chat = await _loadChatBrain(chatInfo.path!);
      try {
        final pipeline = ChatInferencePipeline(
          reasoner: QwenReasoningService(chat),
          tutor: TutorPipeline(engine: chat),
        );
        final clock = Stopwatch()..start();
        final turn = await pipeline.completeTurn(
          userText: 'What is photosynthesis?',
          languageCode: 'en',
          useCurriculum: false,
        );
        debugPrint('CHAT EN (${clock.elapsed.inMilliseconds} ms): '
            '${turn.displayText}');
        expect(turn.displayText.trim(), isNotEmpty);
        englishReply = turn.displayText;
      } finally {
        await chat.dispose();
        debugPrint('UNLOAD CHAT');
      }

      final afrislm = LlamaCppEngineImpl(
        schedulerLane: EngineLane.translate,
        backendLabel: 'llama.cpp · AfriSLM 0.8B',
      );
      await afrislm.loadModel(afrislmInfo.path!);
      debugPrint('LOADED AFRISLM');
      addTearDown(afrislm.dispose);

      final translator = TranslationPipeline(afrislm, modelTag: 'e2e-chat');

      const outbound = <(String, String)>[
        ('lg', 'How are you?'),
        ('sw', 'Water travels up from the roots.'),
        ('rw', 'Write the equation'),
        ('so', 'How are you?'),
        ('ln', 'How are you?'),
      ];
      for (final pair in outbound) {
        final hop = await translator.fromEnglishDetailed(pair.$2, pair.$1);
        debugPrint(
          'OUT ${pair.$1}: translated=${hop.translated} '
          'failure=${hop.failure} text=${hop.text}',
        );
        expect(hop.text.trim(), isNotEmpty);
        expect(hop.translated, isTrue,
            reason: 'en→${pair.$1} failed: ${hop.failure} raw=${hop.text}');
      }

      const inbound = <(String, String)>[
        ('lg', 'Oli otya?'),
        ('sw', 'Habari yako?'),
        ('rw', 'Mwaramutse?'),
        ('so', 'Sidee tahay?'),
        ('ln', 'Ndenge nini?'),
      ];
      for (final pair in inbound) {
        final hop = await translator.toEnglishDetailed(pair.$2, pair.$1);
        debugPrint(
          'IN ${pair.$1}: translated=${hop.translated} '
          'failure=${hop.failure} text=${hop.text}',
        );
        expect(hop.translated, isTrue,
            reason: '${pair.$1}→en failed: ${hop.failure} raw=${hop.text}');
      }

      for (final lang in ['lg', 'sw']) {
        final hop =
            await translator.fromEnglishDetailed(englishReply, lang);
        debugPrint(
          'CHAT OUT $lang: translated=${hop.translated} text=${hop.text}',
        );
        expect(hop.text.trim(), isNotEmpty);
        expect(hop.translated, isTrue,
            reason: 'tutor en→$lang failed: ${hop.failure}');
      }
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
