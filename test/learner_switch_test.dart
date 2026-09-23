import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/db/otic_database.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/learners/learner_switcher.dart';
import 'package:ai_connect_africa/features/teacher/teacher_pin.dart';
import 'package:ai_connect_africa/memory/session_recall_store.dart';
import 'package:ai_connect_africa/services/chat_inference_pipeline.dart';
import 'package:ai_connect_africa/services/qwen_chat_service.dart';

class _EchoEngine extends InferenceEngine {
  final prompts = <String>[];
  int resets = 0;

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
    return 'Here is an answer.';
  }

  @override
  Future<void> resetSession() async => resets++;

  @override
  Future<void> dispose() async {}
}

void main() {
  late OticDatabase db;
  late ProviderContainer container;
  late _EchoEngine engine;
  late Directory recallDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = OticDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    engine = _EchoEngine();
    recallDir = await Directory.systemTemp.createTemp('otic_switch_recall');
    final tutor = TutorPipeline(engine: engine);
    final pipeline = ChatInferencePipeline(
      reasoner: QwenReasoningService(engine),
      tutor: tutor,
    );
    container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(db),
        sessionRecallStoreProvider
            .overrideWithValue(SessionRecallStore(directory: recallDir)),
        chatInferencePipelineProvider.overrideWith((ref) async => pipeline),
        tutorPipelineProvider.overrideWith((ref) async => tutor),
        engineLoadedProvider.overrideWith((ref) async => engine),
      ],
    );
    addTearDown(() async {
      // Recall files are written in the background after a turn; let that
      // finish before the container and folder go away.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      container.dispose();
      await db.close();
      try {
        await recallDir.delete(recursive: true);
      } on FileSystemException {
        // Windows can still hold the last file handle; it's a temp folder.
      }
    });
  });

  Future<int> onboard(String name) async {
    await container
        .read(studentNotifierProvider.notifier)
        .createProfile(name: name);
    return (await container.read(activeStudentProvider.future))!.id;
  }

  test('onboarding still never creates a second profile', () async {
    final first = await onboard('Amina');
    await container
        .read(studentNotifierProvider.notifier)
        .createProfile(name: 'Amina K.');
    final all = await db.studentDao.getAllStudents();
    expect(all, hasLength(1));
    expect(all.single.id, first);
    expect(all.single.name, 'Amina K.');
  });

  test('adding a learner inserts a profile without switching to it',
      () async {
    final amina = await onboard('Amina');
    final brian = await container
        .read(studentNotifierProvider.notifier)
        .addLearner(name: 'Brian', grade: 'P5');

    expect(brian, isNot(amina));
    expect(await db.studentDao.getAllStudents(), hasLength(2));
    container.invalidate(activeStudentProvider);
    expect((await container.read(activeStudentProvider.future))!.id, amina);
  });

  test('switching makes the chosen learner active and remembers it',
      () async {
    await onboard('Amina');
    final brian = await container
        .read(studentNotifierProvider.notifier)
        .addLearner(name: 'Brian');

    await container.read(learnerSwitcherProvider).switchTo(brian);

    expect((await container.read(activeStudentProvider.future))!.name,
        'Brian');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(kActiveStudentIdKey), brian);
    expect(prefs.getString('student_name'), 'Brian');
  });

  test("the next learner never sees the previous learner's conversation",
      () async {
    await onboard('Amina');
    final brian = await container
        .read(studentNotifierProvider.notifier)
        .addLearner(name: 'Brian');

    final chat = container.read(chatProvider.notifier);
    await container.read(chatProvider.future);
    await chat.send('What is gravity?');
    expect(container.read(chatProvider).valueOrNull?.messages, isNotEmpty);

    await container.read(learnerSwitcherProvider).switchTo(brian);
    await pumpEventQueue();

    expect(container.read(chatProvider).valueOrNull?.messages, isEmpty);
    expect(engine.resets, greaterThan(0),
        reason: 'engine KV session must be dropped on switch');

    await container.read(chatProvider.notifier).send('What is a cell?');
    expect(engine.prompts.last, isNot(contains('gravity')));
  });

  test('handing the device to a learner locks the teacher area again',
      () async {
    await onboard('Amina');
    final brian = await container
        .read(studentNotifierProvider.notifier)
        .addLearner(name: 'Brian');
    container.read(teacherUnlockedProvider.notifier).state = true;

    await container.read(learnerSwitcherProvider).switchTo(brian);

    expect(container.read(teacherUnlockedProvider), isFalse);
  });

  test('a saved choice pointing at a deleted learner falls back', () async {
    final amina = await onboard('Amina');
    final brian = await container
        .read(studentNotifierProvider.notifier)
        .addLearner(name: 'Brian');
    await container.read(learnerSwitcherProvider).switchTo(brian);

    await db.studentDao.deleteStudent(brian);
    container.invalidate(activeStudentProvider);
    expect((await container.read(activeStudentProvider.future))!.id, amina);
  });
}
