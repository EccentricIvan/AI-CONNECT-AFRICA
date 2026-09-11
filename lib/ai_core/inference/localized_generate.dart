import '../science/science_text.dart';
import '../translate/translation_pipeline.dart';
import '../tutor/tutor_contract.dart';
import 'inference_engine.dart';
import 'runtime_config.dart';

class LocalizedReply {
  const LocalizedReply({
    required this.text,
    this.translatedLanguage,
    this.english,
  });

  /// Student-facing text (translated when a pipeline was available).
  final String text;
  final String? translatedLanguage;

  /// English the tutor actually generated. Create-mode history stays
  /// English so the next turn's prompt is not a translation of a translation.
  final String? english;
}

/// English generate with math-delimiter repair, then optional AfriSLM hop.
Future<LocalizedReply> generateLocalizedReply({
  required InferenceEngine engine,
  required String prompt,
  required String languageCode,
  void Function(String display)? onDisplay,
  String? systemPrompt,
  int maxTokens = kMaxNewTokens,
  double temperature = kTutorTemperature,
  TranslationPipeline? pipeline,
}) async {
  final buf = StringBuffer();
  final text = await engine.generate(
    prompt: prompt,
    systemPrompt: systemPrompt ?? kTutorContract,
    maxTokens: maxTokens,
    temperature: temperature,
    onToken: (token) async {
      buf.write(token);
      onDisplay?.call(repairUnclosedMathDelimiters(buf.toString()));
    },
  );
  final painted = repairUnclosedMathDelimiters(
    buf.toString().isEmpty ? text : buf.toString(),
  );
  onDisplay?.call(painted);

  var display = painted;
  if (languageCode != 'en' &&
      pipeline != null &&
      painted.trim().isNotEmpty &&
      !isMathPassThrough(painted)) {
    final transBuf = StringBuffer();
    final outcome = await pipeline.fromEnglishDetailed(
      painted,
      languageCode,
      onToken: (token) async {
        transBuf.write(token);
        onDisplay?.call(repairUnclosedMathDelimiters(transBuf.toString()));
      },
    );
    if (outcome.translated) {
      display = repairUnclosedMathDelimiters(outcome.text);
      onDisplay?.call(display);
    }
  }

  return LocalizedReply(
    text: display,
    english: painted,
    translatedLanguage: languageCode == 'en' ? null : languageCode,
  );
}
