import 'package:ai_connect_africa/ai_core/inference/engine_scheduler.dart';
import 'package:ai_connect_africa/ai_core/inference/llama_cpp_engine.dart';
import 'package:ai_connect_africa/ai_core/inference/runtime_config.dart';
import 'package:ai_connect_africa/ai_core/model/programming_model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/translation_pipeline.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/services/chat_inference_pipeline.dart';
import 'package:ai_connect_africa/services/qwen_reasoning_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Coder brain (Qwen 1.5B) with AfriSLM. The 0.6B chat brain is not loaded.
///
/// Run this in a fresh process after the chat e2e so llama.cpp never holds
/// 0.6B, 1.5B, and AfriSLM at once.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Qwen 1.5B coder, then AfriSLM for Luganda',
    (tester) async {
      final coderInfo = await ProgrammingModelManager().checkModel();
      final afrislmInfo = await AfriSlmModelManager().checkModel();
      expect(coderInfo.isReady && coderInfo.path != null, isTrue,
          reason: 'Coder GGUF missing: ${coderInfo.status} ${coderInfo.path}');
      expect(afrislmInfo.isReady && afrislmInfo.path != null, isTrue,
          reason: 'AfriSLM missing: ${afrislmInfo.status} ${afrislmInfo.path}');
      debugPrint('CODER ${coderInfo.path}');
      debugPrint('AFRISLM ${afrislmInfo.path}');

      late final String englishReply;
      debugPrint('LOAD CODER');
      final coder = LlamaCppEngineImpl(
        schedulerLane: EngineLane.program,
        backendLabel: 'llama.cpp · Qwen 1.5B Coder',
      );
      await coder.loadModel(coderInfo.path!);
      debugPrint('LOADED CODER');
      try {
        final pipeline = ChatInferencePipeline(
          reasoner: QwenReasoningService(coder),
          tutor: TutorPipeline(
            engine: coder,
            systemPrompt: kProgrammingTutorContract,
            maxTokens: kProgrammingMaxTokens,
            codingCoach: true,
          ),
        );
        final turn = await pipeline.completeTurn(
          userText: 'Teach me a Python print statement',
          languageCode: 'en',
          useCurriculum: false,
        );
        debugPrint('CODER EN: ${turn.displayText}');
        expect(turn.displayText.trim(), isNotEmpty);
        expect(turn.displayText, contains('```'));
        englishReply = turn.displayText;
      } finally {
        await coder.dispose();
        debugPrint('UNLOAD CODER');
      }

      debugPrint('LOAD AFRISLM');
      final afrislm = LlamaCppEngineImpl(
        schedulerLane: EngineLane.translate,
        backendLabel: 'llama.cpp · AfriSLM 0.8B',
      );
      await afrislm.loadModel(afrislmInfo.path!);
      debugPrint('LOADED AFRISLM');
      addTearDown(afrislm.dispose);

      final translator = TranslationPipeline(afrislm, modelTag: 'e2e-coder');
      final inbound = await translator.toEnglishDetailed(
        'Nnyonnyola Python print() mu Luganda.',
        'lg',
      );
      debugPrint(
        'CODER IN lg: translated=${inbound.translated} text=${inbound.text}',
      );
      expect(inbound.translated, isTrue,
          reason: 'lg→en failed: ${inbound.failure}');
      expect(inbound.text.toLowerCase(), contains('print'));

      final outbound =
          await translator.fromEnglishDetailed(englishReply, 'lg');
      debugPrint(
        'CODER OUT lg: translated=${outbound.translated} text=${outbound.text}',
      );
      expect(outbound.text.trim(), isNotEmpty);
      expect(outbound.translated, isTrue,
          reason: 'en→lg failed: ${outbound.failure} raw=${outbound.text}');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
