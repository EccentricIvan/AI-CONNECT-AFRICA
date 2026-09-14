import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/ai_core/science/science_text.dart';
import 'package:ai_connect_africa/ai_core/tutor/school_math.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/curriculum/curriculum_provider.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/l10n/app_locale.dart';
import 'package:ai_connect_africa/l10n/language_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingEngine extends InferenceEngine {
  int generates = 0;

  @override
  bool get isReady => true;
  @override
  String get backendLabel => 'count';

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    TokenCallback? onToken,
    String? systemPrompt,
  }) async {
    generates++;
    fail('Kinyarwanda math must not call the GGUF (generate #$generates)');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  const question = 'Shaka agaciro ka x: 2x + 3 = 11';

  test('Dart solver gets x = 4 from Kinyarwanda wrapping', () {
    final solved = solveSchoolMath(question);
    expect(solved, isNotNull);
    expect(solved!.numericAnswer, 4);
    expect(solved.answer, 'x = 4');
    expect(solved.steps.first.formula, contains('2x'));
    expect(isMathPassThrough(solved.steps.first.formula!), isTrue);
  });

  test('Kinyarwanda algebra skips curriculum RAG', () async {
    final svc = CurriculumService();
    await svc.loadAll();
    expect(queryLooksLikeMath(question), isTrue);
    expect(svc.findBestMatchDetailed(question), isNull);
  });

  test('ChatNotifier Kinyarwanda calculation is Dart-only and fast', () async {
    final engine = _CountingEngine();
    final container = ProviderContainer(
      overrides: [
        activeStudentProvider.overrideWith((ref) async => null),
        engineLoadedProvider.overrideWith((ref) async => engine),
        tutorPipelineProvider.overrideWith(
          (ref) async => TutorPipeline(engine: engine),
        ),
        translationPipelineProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    container.read(languageOverrideProvider.notifier).adoptSaved('rw');

    await container.read(chatProvider.future);
    final sw = Stopwatch()..start();
    await container.read(chatProvider.notifier).send(
          question,
          section: ChatSection.learn,
        );
    final ms = sw.elapsedMilliseconds;

    final state = container.read(chatProvider).valueOrNull;
    expect(state, isNotNull);
    expect(state!.isGenerating, isFalse);
    expect(engine.generates, 0);
    final reply = state.messages.where((m) => !m.isUser).last;
    expect(reply.math, isNotNull);
    expect(reply.math!.numericAnswer, 4);
    expect(reply.math!.answer, 'x = 4');
    expect(reply.math!.steps.first.formula, contains('2x'));
    expect(reply.math!.steps.first.title, 'Andika equation');
    expect(reply.followUp, contains('Ni umwanya wawe'));
    expect(reply.followUp, isNot(contains('Your turn')));
    // Assert Dart-only correctness first; wall-clock is CI-noisy (path_provider
    // / SharedPreferences init on cold containers). Keep a soft bound well
    // under a real GGUF turn (~seconds).
    expect(ms, lessThan(5000), reason: 'math turn took ${ms}ms');
  });

  test('Kinyarwanda chrome exists for math follow-up prefix', () {
    expect(hasUiString('rw', 'Your turn — try this:'), isTrue);
    expect(uiString('rw', 'Your turn — try this:'), 'Ni umwanya wawe — gerageza:');
    expect(hasUiString('rw', 'Write the equation'), isTrue);
  });
}
