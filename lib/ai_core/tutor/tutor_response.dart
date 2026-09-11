import '../../curriculum/curriculum_models.dart';
import 'school_math.dart';

/// A single stage in the tutor pipeline.
enum TutorStage {
  answer,    // Direct answer to the question
  clarify,   // Ask a clarifying question or check understanding
  practice,  // Give an exercise / challenge
  apply,     // Real-world application scenario
  create,    // Prompt the student to build/make something
  reflect,   // Ask them to summarise what they learned
}

/// The full structured response from the tutor pipeline.
class TutorResponse {
  const TutorResponse({
    required this.stage,
    required this.text,
    required this.followUpPrompt,
    required this.topic,
    this.isStreaming = false,
    this.math,
    this.mathCoach = false,
    this.lesson,
  });

  /// Which pipeline stage this response belongs to.
  final TutorStage stage;

  /// The AI-generated text for this stage.
  final String text;

  /// The question or prompt shown to the student after the response.
  final String followUpPrompt;

  /// The detected topic (used for memory engine in Phase 3).
  final String topic;

  /// True while tokens are still streaming in.
  final bool isStreaming;

  /// When set, numbers came from the Dart solver — render as named steps.
  final SchoolMathSolution? math;

  /// Show hint / show-steps chips (solver is coaching this turn).
  final bool mathCoach;

  /// Curriculum lesson matched on the English question this turn.
  final Lesson? lesson;

  TutorResponse copyWith({String? text, bool? isStreaming, SchoolMathSolution? math}) {
    return TutorResponse(
      stage: stage,
      text: text ?? this.text,
      followUpPrompt: followUpPrompt,
      topic: topic,
      isStreaming: isStreaming ?? this.isStreaming,
      math: math ?? this.math,
      mathCoach: mathCoach,
      lesson: lesson,
    );
  }

  String get stageLabel {
    switch (stage) {
      case TutorStage.answer:    return 'Answer';
      case TutorStage.clarify:   return 'Check understanding';
      case TutorStage.practice:  return 'Practice';
      case TutorStage.apply:     return 'Apply it';
      case TutorStage.create:    return 'Create';
      case TutorStage.reflect:   return 'Reflect';
    }
  }
}
