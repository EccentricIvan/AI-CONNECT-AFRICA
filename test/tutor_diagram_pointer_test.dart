import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_contract.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/services/pdf/diagram_detector.dart';

class _Engine extends InferenceEngine {
  final prompts = <String>[];

  @override
  bool get isReady => true;

  @override
  String get backendLabel => 'test';

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
    prompts.add(prompt);
    return 'The heart pumps blood around the body.';
  }

  @override
  Future<void> dispose() async {}
}

final _heart = const DiagramMarker(
  caption: 'Figure 3.2 The human heart',
  page: 14,
  document: 'Biology Term 1',
).format();

String _notes() =>
    'Biology Term 1 — Circulation:\nThe heart has four chambers and pumps '
    'blood through the arteries.\n\n$_heart';

void main() {
  test('a relevant diagram gets a page pointer, streamed and in the reply', () async {
    final engine = _Engine();
    final streamed = StringBuffer();
    final tutor = TutorPipeline(engine: engine, teacherNotes: (_) async => _notes());
    final reply = await tutor.respond(
      studentMessage: 'How does the heart pump blood?',
      onToken: streamed.write,
    );
    expect(engine.prompts.single, contains(kDiagramInstruction));
    expect(reply.text, contains('Diagram: see Figure 3.2 The human heart, page 14 of the PDF "Biology Term 1"'));
    expect(streamed.toString(), contains('page 14 of the PDF'));
  });

  test('the pointer is shown once per topic, again after a reset', () async {
    final tutor = TutorPipeline(engine: _Engine(), teacherNotes: (_) async => _notes());
    final first = await tutor.respond(studentMessage: 'How does the heart pump blood?');
    final second = await tutor.respond(studentMessage: 'Tell me more about the heart chambers');
    expect(first.text, contains('page 14'));
    expect(second.text, isNot(contains('page 14')));

    tutor.reset();
    final afterReset = await tutor.respond(studentMessage: 'How does the heart pump blood?');
    expect(afterReset.text, contains('page 14'));
  });

  test('an unrelated question gets no pointer', () async {
    final tutor = TutorPipeline(engine: _Engine(), teacherNotes: (_) async => _notes());
    final reply = await tutor.respond(studentMessage: 'Why do volcanoes erupt?');
    expect(reply.text, isNot(contains('page 14')));
  });

  test('the pointer never enters tutor memory', () async {
    final tutor = TutorPipeline(engine: _Engine(), teacherNotes: (_) async => _notes());
    await tutor.respond(studentMessage: 'How does the heart pump blood?');
    expect(tutor.memorySnapshot().toString(), isNot(contains('printed copy')));
  });

  test('notes without a diagram leave the prompt as it was', () async {
    final engine = _Engine();
    final tutor = TutorPipeline(
      engine: engine,
      teacherNotes: (_) async => 'The heart has four chambers and pumps blood.',
    );
    final reply = await tutor.respond(studentMessage: 'How does the heart pump blood?');
    expect(engine.prompts.single, isNot(contains(kDiagramInstruction)));
    expect(reply.text, isNot(contains('Diagram:')));
  });

  test('an answer from the teacher’s notes names them as its source, once '
      'per topic; one without notes names none', () async {
    final tutor = TutorPipeline(engine: _Engine(), teacherNotes: (_) async => _notes());
    final first = await tutor.respond(studentMessage: 'How does the heart pump blood?');
    expect(first.text,
        contains("Source: your teacher's notes — Biology Term 1 — Circulation"));
    final second = await tutor.respond(studentMessage: 'Tell me more about the heart chambers');
    expect(second.text, isNot(contains('Source:')));

    final plain = TutorPipeline(engine: _Engine(), teacherNotes: (_) async => '');
    final general = await plain.respond(studentMessage: 'How does the heart pump blood?');
    expect(general.text, isNot(contains('Source:')));
  });
}
