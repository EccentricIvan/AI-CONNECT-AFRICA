import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../ai_core/tutor/programming_topic.dart';
import '../../ai_core/tutor/school_math.dart';
import '../../ai_core/tutor/tutor_response.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_models.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/language_provider.dart';
import '../../l10n/ui_registry.dart';
import '../../services/ai_model_manager.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/chat_html_preview.dart';
import '../../shared/widgets/curriculum_diagram.dart';
import '../../shared/widgets/generating_indicator.dart';
import '../../shared/widgets/home_atmosphere_background.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/science_rich_text.dart';
import '../../shared/widgets/worked_solution.dart';
import '../../shared/widgets/studio_page.dart';
import '../../memory/session_recall.dart';
import '../../voice/voice_locales.dart';
import '../../voice/voice_provider.dart';
import '../../voice/voice_service.dart';

class _ChatEntry {
  const _ChatEntry({
    required this.text,
    required this.isUser,
    this.lesson,
    this.isError = false,
    this.followUp,
    this.stage,
    this.math,
    this.mathCoach = false,
    this.translationFailure,
    this.recap,
  });
  final String text;
  final bool isUser;

  /// Set on the single entry that opens a reopened chat.
  final SessionRecall? recap;
  final Lesson? lesson;
  final bool isError;
  final String? followUp;
  final TutorStage? stage;
  final SchoolMathSolution? math;
  final bool mathCoach;

  /// Non-null when this reply is shown in English because translation
  /// failed. Rendered as a small note on the bubble — a student learning in
  /// Swahili must not be left guessing why the tutor switched languages.
  final String? translationFailure;
}

class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({
    super.key,
    this.initialTopic,
    this.section = ChatSection.learn,
    this.programmingSubject = false,
  });
  final String? initialTopic;
  final ChatSection section;
  final bool programmingSubject;

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  VoiceService? _voice;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceServiceProvider);
    scheduleLiteRtMode(ActiveModelMode.chatBrain);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).setSection(widget.section);
      ref.read(chatProvider.notifier).setProgrammingSubject(
            widget.programmingSubject ||
                looksLikeProgramming(widget.initialTopic ?? ''),
          );
      if (widget.initialTopic != null) {
        final topic = widget.initialTopic!;
        _sendText(
          widget.programmingSubject
              ? codingLessonChatOpener(topic)
              : topic,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant LearnScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section) {
      ref.read(chatProvider.notifier).setSection(widget.section);
    }
    if (widget.programmingSubject != oldWidget.programmingSubject) {
      ref.read(chatProvider.notifier).setProgrammingSubject(
            widget.programmingSubject ||
                looksLikeProgramming(widget.initialTopic ?? ''),
          );
    }
    final topic = widget.initialTopic;
    if (topic != null && topic != oldWidget.initialTopic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sendText(
          widget.programmingSubject
              ? codingLessonChatOpener(topic)
              : topic,
        );
      });
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _sendText(text);
  }

  void _onCoachChip(String text) {
    if (text == kCodingChipCheckCode ||
        text.startsWith('Here is my code. Check it')) {
      const prefix = '```python\n';
      _controller.text = '$prefix\n```';
      _controller.selection = const TextSelection.collapsed(offset: prefix.length);
      return;
    }
    _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (ref.read(chatProvider).valueOrNull?.isGenerating ?? false) return;
    _controller.clear();
    ref.read(chatProvider.notifier).send(text, section: widget.section);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleListening() async {
    final voice = ref.read(voiceServiceProvider);
    final listening = ref.read(voiceListeningProvider);

    if (listening) {
      await voice.stopListening();
      ref.read(voiceListeningProvider.notifier).state = false;
      return;
    }

    ref.read(voiceListeningProvider.notifier).state = true;
    final started = await voice.startListening(
      localeId: sttLocaleCandidates(ref.read(appLanguageProvider))
          .first
          .replaceAll('-', '_'),
      onResult: (text, isFinal) {
        if (text.isNotEmpty) {
          _controller.text = text;
          _controller.selection = TextSelection.collapsed(offset: text.length);
        }
        if (isFinal) {
          ref.read(voiceListeningProvider.notifier).state = false;
        }
      },
      onError: (message) {
        ref.read(voiceListeningProvider.notifier).state = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    );
    if (!started) {
      ref.read(voiceListeningProvider.notifier).state = false;
    }
  }

  void _refreshChat() {
    // TTS keeps reading a reply that is about to disappear otherwise.
    _voice?.stopSpeaking();
    ref.read(chatProvider.notifier).reset();
  }

  Future<void> _readAloud(String text) async {
    final voice = ref.read(voiceServiceProvider);
    await voice.speak(text, languageCode: ref.read(appLanguageProvider));
  }

  String _speakable(_ChatEntry entry) {
    if (entry.math != null) {
      final b = StringBuffer();
      final intro = entry.text.trim();
      if (intro.isNotEmpty && !intro.startsWith('Step')) {
        b.writeln(intro);
      }
      for (final s in entry.math!.steps) {
        b.writeln('${s.title}. ${s.why}');
        if (s.formula != null && s.formula!.isNotEmpty) b.writeln(s.formula);
        if (s.calc != null && s.calc!.isNotEmpty) b.writeln(s.calc);
      }
      b.write(entry.math!.answer);
      return b.toString().trim();
    }
    return entry.text;
  }

  @override
  void dispose() {
    _voice?.stopListening();
    _voice?.stopSpeaking();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-resolve chrome + chat I/O the same frame the picker moves.
    ref.watch(appLanguageProvider);
    final chat = ref.watch(chatProvider);
    final isLoading = chat.valueOrNull?.isGenerating ?? false;
    final isWide = MediaQuery.sizeOf(context).width >= 640;
    final bottomPad = isWide ? 16.0 : (AppShell.kNavBarHeight + 24);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.programmingSubject
          ? StudioAppBar(
              title: tr(context, 'Coding chat'),
              subtitle: tr(
                context,
                'Talk through the curriculum, then try the code',
              ),
              icon: Icons.auto_awesome_rounded,
              iconColor: AppColors.accentViolet,
              actions: [
                StudioHeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: tr(context, UiRegistry.newSession),
                  onTap: _refreshChat,
                ),
              ],
            )
          : _HomeChromeAppBar(
              onRefresh: (chat.valueOrNull?.messages.isNotEmpty ?? false)
                  ? _refreshChat
                  : null,
            ),
      body: ScrollConfiguration(
        behavior: const NoScrollbarBehavior(),
        child: MaxWidth(
          maxWidth: 900,
          child: Column(
            children: [
            Expanded(
              child: chat.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (state) {
                  if (state.messages.isEmpty) {
                    return _HomeEmptyWorkspace(
                      coding: widget.programmingSubject,
                      controller: _controller,
                      isLoading: isLoading,
                      isListening: ref.watch(voiceListeningProvider),
                      onMicPressed: _toggleListening,
                      onSend: _send,
                      onCodingTopic: (t) {
                        _controller.text = t;
                        _send();
                      },
                    );
                  }

                  // Build the timeline straight from the chat provider's
                  // messages — the actual chronological order of the
                  // conversation — and slot each lesson card in right after
                  // the question that matched it.
                  final allItems = <_ChatEntry>[];
                  for (final msg in state.messages) {
                    allItems.add(_ChatEntry(
                      text: msg.text,
                      isUser: msg.isUser,
                      isError: msg.isError,
                      followUp: msg.followUp,
                      stage: msg.stage,
                      math: msg.math,
                      mathCoach: msg.mathCoach,
                      translationFailure: msg.translationFailure,
                      recap: msg.recap,
                    ));
                    if (msg.isUser && msg.lesson != null) {
                      allItems.add(_ChatEntry(text: '', isUser: false, lesson: msg.lesson));
                    }
                  }

                  final showGenerating = state.isGenerating;

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: allItems.length + (showGenerating ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= allItems.length) {
                        return StreamBuilder<String>(
                          stream: state.turnTokens,
                          builder: (context, snapshot) {
                            final text = (snapshot.data != null &&
                                    snapshot.data!.isNotEmpty)
                                ? snapshot.data!
                                : state.streamingText;
                            if (state.streamingMath != null) {
                              return _TutorBubble(
                                text: text,
                                stage: null,
                                math: state.streamingMath,
                                codingCoach: widget.programmingSubject,
                                isStreaming: true,
                              );
                            }
                            if (text.isNotEmpty) {
                              return _TutorBubble(
                                text: text,
                                stage: null,
                                codingCoach: widget.programmingSubject,
                                isStreaming: true,
                              );
                            }
                            return const GeneratingIndicator();
                          },
                        );
                      }

                      final entry = allItems[i];

                      // Recap of a reopened chat — never a message bubble,
                      // because the stored gist is clipped and fake bubbles
                      // would look like the conversation was mangled.
                      if (entry.recap != null) {
                        return _RecapCard(recall: entry.recap!);
                      }

                      // Lesson card from curriculum
                      if (entry.lesson != null) {
                        return _LessonCard(lesson: entry.lesson!);
                      }

                      // User bubble
                      if (entry.isUser) return _UserBubble(text: entry.text);

                      if (entry.isError) {
                        // Error copy is written in English at the source, so
                        // it has to go through the tables like any other
                        // string or it shows English to a Swahili student.
                        return _ErrorBubble(text: tr(context, entry.text));
                      }

                      return _TutorBubble(
                        text: entry.text,
                        stage: entry.stage,
                        math: entry.math,
                        mathCoach: entry.mathCoach,
                        codingCoach: widget.programmingSubject ||
                            entry.text.contains('```'),
                        translationFailure: entry.translationFailure,
                        onChip: _onCoachChip,
                        onReadAloud: _speakable(entry).isNotEmpty
                            ? () => _readAloud(_speakable(entry))
                            : null,
                        isSpeaking:
                            ref.watch(voiceSpeakingProvider) == _speakable(entry),
                      );
                    },
                  );
                },
              ),
            ),
            if (chat.valueOrNull?.messages.isNotEmpty ?? false) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, UiRegistry.offlineChip),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
                child: _ComposerBar(
                  controller: _controller,
                  onSend: _send,
                  isLoading: isLoading,
                  isListening: ref.watch(voiceListeningProvider),
                  onMicPressed: _toggleListening,
                  showMic: true,
                  coding: widget.programmingSubject,
                  compact: false,
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

// ── Chat bubbles ──────────────────────────────────────────────────────────────

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF5C2C0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFFC62828)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF5C1A1A),
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header shown when a saved chat is reopened.
///
/// What is stored is a compressed recall, not a transcript — each line is
/// clipped to roughly a sentence. Drawing those as ordinary message bubbles
/// would show a student their own words cut off mid-thought and read as lost
/// data, so the recall gets one clearly-labelled card instead and the thread
/// below it starts empty. The tutor's memory has already been restored, so
/// the next question continues the lesson rather than starting over.
class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.recall});

  final SessionRecall recall;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    // Oldest first reads as a story; only the tail is kept for long chats.
    final shown = recall.exchanges.length > 6
        ? recall.exchanges.sublist(recall.exchanges.length - 6)
        : recall.exchanges;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ac.iconWell.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ac.textHint.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 15, color: ac.textHint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(context, 'Picking up where you left off'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ac.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (recall.title.trim().isNotEmpty)
            Text(
              recall.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ac.textPrimary,
              ),
            ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final e in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.question.trim().isNotEmpty)
                      Text(
                        '${tr(context, 'You asked')}: ${e.question}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: ac.textPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    if (e.answer.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          e.answer,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: ac.textHint,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 2),
          Text(
            tr(context,
                'This is a short summary of that chat, not the full conversation. Ask your next question to carry on.'),
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              fontStyle: FontStyle.italic,
              color: ac.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: ScienceRichText(
          text: text,
          color: Colors.white,
          style: const TextStyle(color: Colors.white, height: 1.5),
        ),
      ),
    );
  }
}

class _TutorBubble extends StatelessWidget {
  const _TutorBubble({
    required this.text,
    required this.stage,
    this.math,
    this.mathCoach = false,
    this.codingCoach = false,
    this.onChip,
    this.onReadAloud,
    this.isSpeaking = false,
    this.translationFailure,
    this.isStreaming = false,
  });

  final String text;
  final TutorStage? stage;
  final SchoolMathSolution? math;
  final bool mathCoach;
  final bool codingCoach;
  final void Function(String text)? onChip;
  final VoidCallback? onReadAloud;
  final bool isSpeaking;
  final String? translationFailure;

  /// True while this turn is still streaming tokens — the HTML browser
  /// cards only mount once the reply (and its code fences) have settled,
  /// so the WebView isn't torn down and rebuilt on every token.
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/ai-connect-africa-logo.png',
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                    semanticLabel: 'Logo',
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tr(
                      context,
                      codingCoach ? _codingLabel(stage!) : _label(stage!),
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
            ),
          if (translationFailure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate_outlined,
                      size: 12, color: Theme.of(context).hintColor),
                  const SizedBox(width: 4),
                  Text(
                    tr(context, 'Shown in English - translation unavailable'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (math != null) ...[
                  if (text.trim().isNotEmpty &&
                      !text.trimLeft().startsWith('Step'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ScienceRichText(
                        text: text,
                        color: cs.onSurface,
                        style: TextStyle(color: cs.onSurface, height: 1.6),
                      ),
                    ),
                  WorkedSolutionView(solution: math!),
                ] else
                  ScienceRichText(
                    text: text,
                    color: cs.onSurface,
                    style: TextStyle(
                      color: cs.onSurface,
                      height: 1.6,
                    ),
                  ),
                if (!isStreaming)
                  for (final block in extractHtmlBlocksFromChat(text))
                    ChatHtmlPreviewCard(html: block),
                if (onReadAloud != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onReadAloud,
                      icon: Icon(
                        isSpeaking
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                        size: 18,
                      ),
                      label: Text(
                        isSpeaking
                            ? tr(context, 'Stop reading')
                            : tr(context, 'Read aloud'),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onChip != null && mathCoach)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(context, 'Give me a hint')),
                    onPressed: () => onChip!('Give me a hint'),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(context, 'Show the full steps')),
                    onPressed: () => onChip!('Show the full steps'),
                  ),
                ],
              ),
            ),
          if (onChip != null && codingCoach)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(context, kCodingChipTryExample)),
                    onPressed: () => onChip!(
                      'I tried the example. Explain what each line does.',
                    ),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(context, kCodingChipCheckCode)),
                    onPressed: () => onChip!(kCodingChipCheckCode),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(context, kCodingChipPractice)),
                    onPressed: () => onChip!(kCodingChipPractice),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(tr(context, kCodingChipNext)),
                    onPressed: () => onChip!(kCodingChipNext),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _codingLabel(TutorStage s) {
    switch (s) {
      case TutorStage.answer:
        return 'Coding tutor - Teach';
      case TutorStage.clarify:
        return 'Coding tutor - Check';
      case TutorStage.practice:
        return 'Coding tutor - Practice';
      case TutorStage.apply:
        return 'Coding tutor - Apply';
      case TutorStage.create:
        return 'Coding tutor - Build';
      case TutorStage.reflect:
        return 'Coding tutor - Reflect';
    }
  }

  String _label(TutorStage s) {
    switch (s) {
      case TutorStage.answer:
        return 'AI Tutor - Answer';
      case TutorStage.clarify:
        return 'AI Tutor - Check understanding';
      case TutorStage.practice:
        return 'AI Tutor - Practice';
      case TutorStage.apply:
        return 'AI Tutor - Apply it';
      case TutorStage.create:
        return 'AI Tutor - Create';
      case TutorStage.reflect:
        return 'AI Tutor - Reflect';
    }
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _HomeChromeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeChromeAppBar({this.onRefresh});

  /// Null on the empty workspace — there is no thread to clear yet.
  final VoidCallback? onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 640;

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      titleSpacing: 0,
      title: Padding(
        padding: EdgeInsets.fromLTRB(isWide ? 20 : 2, 0, 12, 0),
        child: Row(
          children: [
            if (!isWide) ...[
              IconButton(
                tooltip: tr(context, 'Menu'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                onPressed: () =>
                    AppShell.mobileScaffoldKey.currentState?.openDrawer(),
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Color(0xFF0B1220),
                  size: 26,
                ),
              ),
              Image.asset(
                'assets/branding/ai-connect-africa-logo.png',
                width: 28,
                height: 28,
                semanticLabel: 'Logo',
              ),
              const SizedBox(width: 6),
              const Text(
                'CONNECT AFRICA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: Color(0xFF0B1220),
                ),
              ),
            ],
            const Spacer(),
            if (onRefresh != null) ...[
              StudioHeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: tr(context, UiRegistry.newSession),
                onTap: onRefresh!,
              ),
              const SizedBox(width: 8),
            ],
            StudioHeaderIconButton(
              icon: Icons.notifications_none_rounded,
              badge: true,
              tooltip: tr(context, 'Achievements'),
              onTap: () => context.push('/achievements'),
            ),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: ac.border,
            ),
            InkWell(
              onTap: () => context.push('/settings'),
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ac.border),
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                        color: Color(0xFF0B1220),
                      ),
                    ),
                    if (isWide) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: ac.textHint,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeEmptyWorkspace extends StatelessWidget {
  const _HomeEmptyWorkspace({
    required this.coding,
    required this.controller,
    required this.isLoading,
    required this.isListening,
    required this.onMicPressed,
    required this.onSend,
    required this.onCodingTopic,
  });

  final bool coding;
  final TextEditingController controller;
  final bool isLoading;
  final bool isListening;
  final VoidCallback onMicPressed;
  final VoidCallback onSend;
  final void Function(String) onCodingTopic;

  static const _codingLessons = [
    'Variables and Data Types',
    'If/Else Decisions',
    'Loops',
    'Functions',
    'What is HTML and Web Pages',
    'Introduction to CSS',
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 640;
    final bottomPad = isWide ? 36.0 : (AppShell.kNavBarHeight + 16);

    // Fixed Home empty layout — no body scrollbar.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 40 : 18,
        0,
        isWide ? 40 : 18,
        bottomPad,
      ),
      child: Column(
        children: [
          const Spacer(flex: 3),
          if (isWide)
            Text(
              'KNOWLEDGE  x  OPPORTUNITY  x  IMPACT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 3.2,
                color: const Color(0xFF9AA6BE),
              ),
            )
          else
            // Mobile: one centered row with spaced words + "x" separators (mockup).
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'KNOWLEDGE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.4,
                      color: Color(0xFF9AA6BE),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'x',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9AA6BE),
                      ),
                    ),
                  ),
                  Text(
                    'OPPORTUNITY',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.4,
                      color: Color(0xFF9AA6BE),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'x',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9AA6BE),
                      ),
                    ),
                  ),
                  Text(
                    'IMPACT',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.4,
                      color: Color(0xFF9AA6BE),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: isWide ? 14 : 10),
          Builder(
            builder: (context) {
              final full = tr(context, 'How can I help you today?');
              // Mobile mockup always breaks the English line; other locales
              // keep the translated string and wrap naturally.
              final text = !isWide && full == 'How can I help you today?'
                  ? 'How can I help\nyou today?'
                  : full;
              return Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: isWide ? 36 : 26,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: -0.4,
                  color: const Color(0xFF0B1220),
                ),
              );
            },
          ),
          // Generous gap before the composer (mockup spacing).
          SizedBox(height: isWide ? 30 : 34),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? 620 : double.infinity,
              ),
              child: _ComposerBar(
                controller: controller,
                onSend: onSend,
                isLoading: isLoading,
                isListening: isListening,
                onMicPressed: onMicPressed,
                showMic: false,
                coding: coding,
                compact: true,
              ),
            ),
          ),
          if (coding) ...[
            SizedBox(height: isWide ? 18 : 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final title in _codingLessons)
                  ActionChip(
                    label: Text(tr(context, title)),
                    onPressed: () =>
                        onCodingTopic(codingLessonChatOpener(title)),
                  ),
              ],
            ),
          ],
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.onSend,
    required this.isLoading,
    required this.isListening,
    required this.onMicPressed,
    this.showMic = true,
    this.coding = false,
    this.compact = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isLoading;
  final bool isListening;
  final VoidCallback onMicPressed;
  final bool showMic;
  final bool coding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6ECF7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160B1B4D),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x0A1F6BE5),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      child: Theme(
        // Kill Material hover/fill overlay on the desktop composer.
        data: Theme.of(context).copyWith(
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                Icons.attach_file_rounded,
                color: Color(0xFF9AA6BE),
                size: 22,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onSend(),
                mouseCursor: SystemMouseCursors.text,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  hintText: isListening
                      ? tr(context, UiRegistry.listening)
                      : tr(
                          context,
                          coding
                              ? 'Ask about this lesson or paste your code…'
                              : 'Ask anything...',
                        ),
                  hintStyle: const TextStyle(
                    fontFamily: 'Inter',
                    color: Color(0xFF9AA6BE),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 12,
                  ),
                ),
                cursorColor: const Color(0xFF2F7BF0),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF0B1220),
                ),
                maxLines: compact ? 2 : 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
              ),
            ),
            if (showMic)
              IconButton(
                onPressed: isLoading ? null : onMicPressed,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                icon: Icon(isListening ? Icons.mic : Icons.mic_none_outlined),
                color:
                    isListening ? AppColors.primary : const Color(0xFF9AA6BE),
                tooltip: isListening
                    ? tr(context, 'Stop dictation')
                    : tr(context, 'Speak your question'),
              ),
            const SizedBox(width: 4),
            isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                // No Material splash — mockups show a clean circular gradient only.
                : Semantics(
                    button: true,
                    label: tr(context, UiRegistry.send),
                    child: GestureDetector(
                      onTap: onSend,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF3B82F6),
                              Color(0xFF6366F1),
                              Color(0xFF7C3AED),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Lesson card shown in chat ────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson});
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.practiceColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.menu_book, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(lesson.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Curriculum', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              lesson.content.length > 300 ? '${lesson.content.substring(0, 300)}...' : lesson.content,
              style: TextStyle(fontSize: 13, height: 1.6, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          if (lesson.diagram != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: CurriculumDiagram(
                assetPath: lesson.diagram!,
                semanticLabel: '${lesson.title} diagram',
              ),
            ),
          if (lesson.examples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.createColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.createColor.withValues(alpha: 0.12)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Example', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.createColor)),
                  const SizedBox(height: 4),
                  Text(lesson.examples.first, style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.onSurface)),
                ]),
              ),
            ),
          if (lesson.keyTerms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: lesson.keyTerms.keys.take(4).map((term) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Text(term, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
