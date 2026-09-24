import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/ai_core/inference/inference_engine.dart';
import 'package:ai_connect_africa/ai_core/providers/ai_provider.dart';
import 'package:ai_connect_africa/ai_core/tutor/tutor_pipeline.dart';
import 'package:ai_connect_africa/db/providers/db_provider.dart';
import 'package:ai_connect_africa/features/learn/learn_screen.dart';
import 'package:ai_connect_africa/l10n/app_locale.dart';
import 'package:ai_connect_africa/l10n/language_provider.dart';
import 'package:ai_connect_africa/services/chat_inference_pipeline.dart';
import 'package:ai_connect_africa/shared/widgets/studio_page.dart';
import 'package:ai_connect_africa/voice/voice_provider.dart';
import 'package:ai_connect_africa/voice/voice_service.dart';

class _SilentVoice extends VoiceService {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String languageCode = 'en'}) async {}

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    String localeId = '',
  }) async =>
      false;
}

/// Seeds a thread so the refresh control has something to clear.
class _SeededChat extends ChatNotifier {
  @override
  Future<ChatState> build() async => const ChatState(
        messages: [ChatMessage(text: 'What is gravity?', isUser: true)],
      );
}

Future<BuildContext> _pumpChat(
  WidgetTester tester,
  String languageCode, {
  bool programming = false,
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      activeStudentProvider.overrideWith((ref) async => null),
      voiceServiceProvider.overrideWithValue(_SilentVoice()),
      // reset() reaches for these; leaving them unresolved keeps widget
      // tests away from model loading.
      chatInferencePipelineProvider
          .overrideWith((ref) => Completer<ChatInferencePipeline>().future),
      tutorPipelineProvider
          .overrideWith((ref) => Completer<TutorPipeline>().future),
      engineLoadedProvider
          .overrideWith((ref) => Completer<InferenceEngine>().future),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  container.read(languageOverrideProvider.notifier).adoptSaved(languageCode);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AppLocale(
          languageCode: languageCode,
          child: LearnScreen(programmingSubject: programming),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tester.element(find.byType(LearnScreen));
}

void main() {
  testWidgets('chat header does not show model or backend details', (tester) async {
    await _pumpChat(tester, 'en');

    expect(find.textContaining('LiteRT'), findsNothing);
    expect(find.textContaining('Qwen'), findsNothing);
    expect(find.textContaining('CPU'), findsNothing);
    expect(find.textContaining('0.6B'), findsNothing);
    expect(find.text('Demo'), findsNothing);
  });

  testWidgets(
      'chat chrome follows English, Luganda, Kinyarwanda, Swahili',
      (tester) async {
    const langs = ['en', 'lg', 'rw', 'sw'];
    for (final code in langs) {
      final ctx = await _pumpChat(tester, code);
      expect(
        find.textContaining(tr(ctx, 'how can I help you?')),
        findsWidgets,
        reason: '$code: Home greeting missing',
      );
      expect(
        find.text(tr(ctx, 'Ask anything...')),
        findsWidgets,
        reason: '$code: composer placeholder missing',
      );
    }
  });

  testWidgets('refresh clears the thread and is hidden while empty',
      (tester) async {
    final ctx = await _pumpChat(
      tester,
      'en',
      overrides: [chatProvider.overrideWith(_SeededChat.new)],
    );
    final container = ProviderScope.containerOf(ctx);
    final refresh = find.widgetWithIcon(
      StudioHeaderIconButton,
      Icons.refresh_rounded,
    );

    expect(find.text('What is gravity?'), findsOneWidget);
    expect(refresh, findsOneWidget);

    await tester.tap(refresh);
    await tester.pump();

    expect(find.text('What is gravity?'), findsNothing);
    expect(
      container.read(chatProvider).valueOrNull?.messages,
      isEmpty,
    );
    expect(refresh, findsNothing, reason: 'nothing left to refresh');
  });

  testWidgets('coding empty state offers curriculum lessons', (tester) async {
    await _pumpChat(tester, 'en', programming: true);

    expect(find.text('Coding chat'), findsWidgets);
    expect(find.text('Variables and Data Types'), findsOneWidget);
    expect(find.text('If/Else Decisions'), findsOneWidget);
    expect(
      find.text('Ask about this lesson or paste your code…'),
      findsOneWidget,
    );
  });
}
