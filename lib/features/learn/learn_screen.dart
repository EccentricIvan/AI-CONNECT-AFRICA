import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../ai_core/tutor/school_math.dart';
import '../../ai_core/tutor/tutor_response.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_models.dart';
import '../../curriculum/curriculum_provider.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/language_provider.dart';
import '../../l10n/ui_registry.dart';
import '../../shared/widgets/curriculum_diagram.dart';
import '../../shared/widgets/generating_indicator.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/worked_solution.dart';
import '../../shared/widgets/studio_page.dart';
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
  });
  final String text;
  final bool isUser;
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
  const LearnScreen({super.key, this.initialTopic});
  final String? initialTopic;

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
    if (widget.initialTopic != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendText(widget.initialTopic!);
      });
    }
  }

  // Lesson cards keyed by the exact user message text that matched them, so
  // they can be inserted right after that question in the render below —
  // rather than kept in a separate list that has to be merged with the chat
  // provider's messages (which broke ordering once 2+ turns were in flight:
  // both questions landed together, followed by both answers).
  final Map<String, Lesson> _lessonForMessage = {};

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (ref.read(chatProvider).valueOrNull?.isGenerating ?? false) return;
    _controller.clear();
    ref.read(chatProvider.notifier).send(text);
    _scrollToBottom();
    unawaited(_attachLessonCard(text));
  }

  Future<void> _attachLessonCard(String text) async {
    // Match against the student's text as typed. A second AfriSLM call here
    // raced the chat translation and doubled wait time. English topic words
    // still match; the tutor already searches curriculum on the English
    // version of the question.
    final curriculum = ref.read(curriculumServiceProvider);
    final lesson = curriculum.findBestMatch(text);
    if (lesson != null && mounted) {
      setState(() => _lessonForMessage[text] = lesson);
    }
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

  Future<void> _readAloud(String text) async {
    final voice = ref.read(voiceServiceProvider);
    await voice.speak(text);
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
    final aiStatus = ref.watch(aiStatusProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'AI Chat'),
        subtitle: tr(context, 'Ask anything, learn together'),
        icon: Icons.auto_awesome_rounded,
        iconColor: const Color(0xFF7B6CF6),
        actions: [
          aiStatus.when(
            data: (status) => Chip(
              avatar: Icon(
                status.isDemo ? Icons.info_outline : Icons.memory,
                size: 14,
                color: status.isDemo
                    ? const Color(0xFFB86E00)
                    : AppColors.teachColor,
              ),
              label: Text(
                status.isDemo
                    ? tr(context, 'Demo')
                    : (status.backendLabel ?? tr(context, 'AI')),
                style: TextStyle(
                  fontSize: 11,
                  color: status.isDemo
                      ? const Color(0xFFB86E00)
                      : AppColors.teachColor,
                ),
              ),
              backgroundColor: status.isDemo
                  ? const Color(0xFFFFF8E7)
                  : AppColors.teachColor.withValues(alpha: 0.08),
              side: BorderSide(
                color: status.isDemo
                    ? const Color(0xFFE8D4A8)
                    : AppColors.teachColor.withValues(alpha: 0.3),
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            loading: () => const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          StudioHeaderIconButton(
            icon: Icons.refresh_rounded,
            tooltip: tr(context, UiRegistry.newSession),
            onTap: () => ref.read(chatProvider.notifier).reset(),
          ),
        ],
      ),
      body: MaxWidth(
        child: Column(
          children: [
            Expanded(
              child: chat.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (state) {
                  if (state.messages.isEmpty) {
                    return _EmptyState(
                      onTopic: (t) {
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
                    ));
                    if (msg.isUser) {
                      final lesson = _lessonForMessage[msg.text];
                      if (lesson != null) {
                        allItems.add(_ChatEntry(text: '', isUser: false, lesson: lesson));
                      }
                    }
                  }

                  final showGenerating = state.isGenerating;

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: allItems.length + (showGenerating ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= allItems.length) {
                        if (state.streamingText.isNotEmpty) {
                          return _TutorBubble(
                            text: state.streamingText,
                            stage: null,
                            followUp: null,
                          );
                        }
                        return const GeneratingIndicator();
                      }

                      final entry = allItems[i];

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
                        followUp: entry.followUp == null
                            ? null
                            : tr(context, entry.followUp!),
                        math: entry.math,
                        mathCoach: entry.mathCoach,
                        translationFailure: entry.translationFailure,
                        onChip: _sendText,
                        onReadAloud: entry.text.isNotEmpty ? () => _readAloud(entry.text) : null,
                        isSpeaking: ref.watch(voiceSpeakingProvider) == entry.text,
                      );
                    },
                  );
                },
              ),
            ),
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
            _InputBar(
              controller: _controller,
              onSend: _send,
              isLoading: chat.valueOrNull?.isGenerating ?? false,
              isListening: ref.watch(voiceListeningProvider),
              onMicPressed: _toggleListening,
            ),
          ],
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
        child: Text(
          text,
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
    required this.followUp,
    this.math,
    this.mathCoach = false,
    this.onChip,
    this.onReadAloud,
    this.isSpeaking = false,
    this.translationFailure,
  });

  final String text;
  final TutorStage? stage;
  final String? followUp;
  final SchoolMathSolution? math;
  final bool mathCoach;
  final void Function(String text)? onChip;
  final VoidCallback? onReadAloud;
  final bool isSpeaking;
  final String? translationFailure;

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
                    tr(context, _label(stage!)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            child: math != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (text.trim().isNotEmpty &&
                          !text.trimLeft().startsWith('Step'))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            text,
                            style: TextStyle(color: cs.onSurface, height: 1.6),
                          ),
                        ),
                      WorkedSolutionView(solution: math!),
                    ],
                  )
                : Text(
                    text,
                    style: TextStyle(
                      color: cs.onSurface,
                      height: 1.6,
                    ),
                  ),
          ),
          if (followUp != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Text(
                followUp!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                  fontStyle: FontStyle.italic,
                ),
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
          if (onReadAloud != null && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 2),
              child: TextButton.icon(
                onPressed: onReadAloud,
                icon: Icon(
                  isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                  size: 18,
                ),
                label: Text(isSpeaking ? tr(context, 'Stop reading') : tr(context, 'Read aloud')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
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

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.isLoading,
    required this.isListening,
    required this.onMicPressed,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isLoading;
  final bool isListening;
  final VoidCallback onMicPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      child: Row(
        children: [
          IconButton(
            onPressed: isLoading ? null : onMicPressed,
            icon: Icon(isListening ? Icons.mic : Icons.mic_none_outlined),
            color: isListening ? AppColors.primary : null,
            tooltip: isListening
                ? tr(context, 'Stop dictation')
                : tr(context, 'Speak your question'),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: isListening
                    ? tr(context, UiRegistry.listening)
                    : tr(context, UiRegistry.askPlaceholder),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : IconButton.filled(
                  onPressed: onSend,
                  tooltip: tr(context, UiRegistry.send),
                  icon: const Icon(Icons.arrow_upward),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Empty / starter state ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTopic});
  final void Function(String) onTopic;

  static const _starter = 'Ask me anything';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.practiceColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/branding/ai-connect-africa-logo.png',
                fit: BoxFit.contain,
                semanticLabel: 'Logo',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr(context, 'AI Chat'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Ask questions, get explanations, and explore any topic with your AI tutor.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 28),
          InkWell(
            onTap: () => onTopic(_starter),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.practiceColor.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'Start a conversation'),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
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
