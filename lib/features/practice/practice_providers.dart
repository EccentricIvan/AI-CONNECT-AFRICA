import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import 'scenario_generator.dart';
import 'scenario_models.dart';

// ── Apply (scenario) session ──────────────────────────────────────────────────

class ApplyState {
  const ApplyState({
    this.topic = '',
    this.scenario,
    this.response = '',
    this.feedback,
    this.isGeneratingScenario = false,
    this.isEvaluating = false,
    this.error,
    this.scenariosEvaluated = 0,
  });

  final String topic;
  final Scenario? scenario;
  final String response;
  final String? feedback;
  final bool isGeneratingScenario;
  final bool isEvaluating;
  final String? error;
  final int scenariosEvaluated;

  ApplyState copyWith({
    String? topic,
    Scenario? scenario,
    String? response,
    String? feedback,
    bool? isGeneratingScenario,
    bool? isEvaluating,
    String? error,
    int? scenariosEvaluated,
    bool clearScenario = false,
    bool clearFeedback = false,
    bool clearError = false,
  }) =>
      ApplyState(
        topic: topic ?? this.topic,
        scenario: clearScenario ? null : scenario ?? this.scenario,
        response: response ?? this.response,
        feedback: clearFeedback ? null : feedback ?? this.feedback,
        isGeneratingScenario:
            isGeneratingScenario ?? this.isGeneratingScenario,
        isEvaluating: isEvaluating ?? this.isEvaluating,
        error: clearError ? null : error ?? this.error,
        scenariosEvaluated: scenariosEvaluated ?? this.scenariosEvaluated,
      );
}

class ApplyNotifier extends AutoDisposeNotifier<ApplyState> {
  @override
  ApplyState build() => const ApplyState();

  void setTopic(String topic) {
    state = const ApplyState().copyWith(topic: topic);
  }

  void setResponse(String text) {
    state = state.copyWith(response: text, clearFeedback: true);
  }

  Future<void> generateScenario() async {
    if (state.topic.isEmpty) return;
    state = state.copyWith(
        isGeneratingScenario: true,
        clearScenario: true,
        clearFeedback: true,
        clearError: true,
        response: '');
    try {
      final engine = await ref.read(engineLoadedProvider.future);
      final scenario =
          await ScenarioGenerator(engine: engine).generate(topic: state.topic);
      state = state.copyWith(
        scenario: Scenario(
          topic: scenario.topic,
          situation: scenario.situation,
          challenge: scenario.challenge,
          situationEn: scenario.situation,
          challengeEn: scenario.challenge,
        ),
        isGeneratingScenario: false,
      );
    } catch (e) {
      state = state.copyWith(isGeneratingScenario: false, error: e.toString());
    }
  }

  Future<void> evaluate() async {
    final scenario = state.scenario;
    if (scenario == null || state.response.trim().isEmpty) return;
    state = state.copyWith(isEvaluating: true, clearFeedback: true);
    try {
      final engine = await ref.read(engineLoadedProvider.future);
      final feedback = await ScenarioGenerator(engine: engine).evaluate(
        topic: state.topic,
        situation: scenario.situationEn ?? scenario.situation,
        challenge: scenario.challengeEn ?? scenario.challenge,
        studentResponse: state.response,
      );
      final newCount = state.scenariosEvaluated + 1;
      state = state.copyWith(
        feedback: feedback,
        isEvaluating: false,
        scenariosEvaluated: newCount,
      );

      final student = await ref.read(activeStudentProvider.future);
      if (student != null) {
        await ref.read(badgeServiceProvider).onApplyEvaluated(student.id);
      }
    } catch (e) {
      state = state.copyWith(isEvaluating: false, error: e.toString());
    }
  }

  void nextScenario() {
    state = ApplyState(topic: state.topic, scenariosEvaluated: state.scenariosEvaluated);
    generateScenario();
  }
}

final applyProvider =
    AutoDisposeNotifierProvider<ApplyNotifier, ApplyState>(ApplyNotifier.new);
