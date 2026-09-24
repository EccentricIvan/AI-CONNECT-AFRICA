import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/inference/localized_generate.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/generating_indicator.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import 'package:drift/drift.dart' show Value;
import '../app_dev_lab/app_chat_builder_screen.dart';
import '../app_dev_lab/app_dev_lab_screen.dart';
import '../python_lab/python_lab_screen.dart';
import '../site_builder/site_chat_builder_screen.dart';
import '../web_dev_lab/web_dev_lab_screen.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class _CreateState {
  const _CreateState({
    this.projectType = '',
    this.topic = '',
    this.messages = const [],
    this.isGenerating = false,
    this.streamingText = '',
    this.savedProjectId,
  });

  final String projectType;
  final String topic;
  final List<_Msg> messages;
  final bool isGenerating;
  final String streamingText;
  final int? savedProjectId;

  bool get started => messages.isNotEmpty;

  _CreateState copyWith({
    String? projectType,
    String? topic,
    List<_Msg>? messages,
    bool? isGenerating,
    String? streamingText,
    int? savedProjectId,
  }) => _CreateState(
    projectType: projectType ?? this.projectType,
    topic: topic ?? this.topic,
    messages: messages ?? this.messages,
    isGenerating: isGenerating ?? this.isGenerating,
    streamingText: streamingText ?? this.streamingText,
    savedProjectId: savedProjectId ?? this.savedProjectId,
  );
}

class _Msg {
  const _Msg({required this.text, required this.isUser, this.english});
  final String text;
  final bool isUser;

  /// English the brain saw or produced. [text] is what the student reads.
  final String? english;
}

class _CreateNotifier extends AutoDisposeNotifier<_CreateState> {
  @override
  _CreateState build() => const _CreateState();

  void setType(String t) => state = state.copyWith(projectType: t);
  void setTopic(String t) => state = state.copyWith(topic: t);

  Future<void> start() async {
    if (state.projectType.isEmpty || state.topic.isEmpty) return;
    final intro =
        'I want to create a ${state.projectType} about ${state.topic}.';
    await _send(intro);
  }

  Future<void> send(String text) => _send(text);

  Future<void> _send(String userText) async {
    final lang = await studentLanguageCode(ref);
    final msgs = [
      ...state.messages,
      _Msg(text: userText, isUser: true, english: userText),
    ];
    state = state.copyWith(
      messages: msgs,
      isGenerating: true,
      streamingText: '',
    );

    try {
      final engine = state.projectType == 'Code Plan'
          ? await ref.read(programmingEngineProvider.future)
          : await ref.read(engineLoadedProvider.future);
      final prior = state.messages.length > 1
          ? state.messages.sublist(0, state.messages.length - 1)
          : const <_Msg>[];
      // Keep history in the language the student is using.
      final history = prior
          .map((m) =>
              '${m.isUser ? 'Student' : 'Tutor'}: ${m.english ?? m.text}')
          .join('\n');

      final prompt =
          '''You are a creative project mentor.
Help the student build a ${state.projectType} about "${state.topic}".
Guide them one step at a time: plan → draft → review.
Ask one clear question or give one clear instruction. Be encouraging.
Keep responses concise (3-5 sentences max).

${history.isNotEmpty ? 'Conversation so far:\n$history\n' : ''}Student: $userText
Tutor:''';

      final localized = await generateLocalizedReply(
        engine: engine,
        prompt: prompt,
        languageCode: lang,
        pipeline: await ensureTranslationPipeline(ref),
        maxTokens: 350,
        temperature: 0.8,
        onDisplay: (shown) {
          state = state.copyWith(streamingText: shown);
        },
      );
      state = state.copyWith(
        messages: [
          ...state.messages,
          _Msg(
            text: localized.text,
            isUser: false,
            english: localized.english,
          ),
        ],
        isGenerating: false,
        streamingText: '',
      );
    } catch (_) {
      state = state.copyWith(isGenerating: false, streamingText: '');
    }
  }

  Future<void> saveProject(BuildContext context) async {
    final student = await ref.read(activeStudentProvider.future);
    if (student == null) return;

    final db = ref.read(dbProvider);
    final stepsJson = jsonEncode(
      state.messages
          .map((m) => {'role': m.isUser ? 'user' : 'otic', 'text': m.text})
          .toList(),
    );

    final title = '${state.projectType}: ${state.topic}';
    final id = await db.projectDao.saveProject(
      StudentProjectsCompanion.insert(
        studentId: student.id,
        title: title,
        topic: state.topic,
        projectType: state.projectType.toLowerCase().replaceAll(' ', '_'),
        stepsJson: Value(stepsJson),
        status: const Value('complete'),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    state = state.copyWith(savedProjectId: id);

    // Award badge
    final badges = await ref
        .read(badgeServiceProvider)
        .onProjectSaved(student.id);
    ref.invalidate(studentProjectsProvider(student.id));

    if (context.mounted) {
      final badgeMsg = badges.isNotEmpty
          ? '\n🏅 Badge earned: ${badges.first.name}!'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project saved!$badgeMsg'),
          backgroundColor: AppColors.teachColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

final _createProvider =
    AutoDisposeNotifierProvider<_CreateNotifier, _CreateState>(
      _CreateNotifier.new,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_createProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // The lab switcher below carries its own top tab row, and every lab it
      // hosts already has its own StudioAppBar/AppBar — a "Create" bar here
      // too would stack three headers. Only the (currently unreachable, see
      // _CreateNotifier — nothing calls setType/setTopic/start) guided-chat
      // fallback still needs one.
      appBar: state.started
          ? StudioAppBar(
              title: '${state.projectType}: ${state.topic}',
              subtitle: tr(context, 'Build step by step with AI'),
              icon: Icons.lightbulb_rounded,
              iconColor: const Color(0xFFFF8A3D),
              actions: [
                if (state.savedProjectId == null && !state.isGenerating)
                  StudioHeaderIconButton(
                    icon: Icons.save_outlined,
                    tooltip: tr(context, 'Save'),
                    onTap: () => ref
                        .read(_createProvider.notifier)
                        .saveProject(context),
                  ),
                StudioHeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: tr(context, 'New project'),
                  onTap: () => ref.invalidate(_createProvider),
                ),
              ],
            )
          : null,
      body: state.started
          ? _ChatView(
              state: state,
              scrollController: _scrollController,
              messageController: _messageController,
              onScrollToBottom: _scrollToBottom,
            )
          : const _SetupView(),
    );
  }
}

// ── Setup view: a horizontal tab row switching between the 5 labs inline ──────
//
// Each lab keeps its own screen widget (own Scaffold, own AppBar, own state)
// completely unchanged — this only changes how a student reaches it: tapping
// a tab swaps which one is shown below, in place, with no route push and no
// page transition. IndexedStack keeps every lab the student has visited
// mounted (so switching back doesn't lose it), and a lab that hasn't been
// opened yet isn't built at all, so all 5 don't eagerly spin up their models
// and state at once.

class _SetupView extends ConsumerStatefulWidget {
  const _SetupView();

  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

typedef _LabTab = ({String title, WidgetBuilder builder});

class _SetupViewState extends ConsumerState<_SetupView> {
  int _active = 0;
  final Set<int> _visited = {0};

  static List<_LabTab> _tabs(BuildContext context) => [
        // Two guided builders, then two code labs, then Python. No entry
        // promises that a model builds the project any more: every section
        // paints from the student's own code, and the coding model is an
        // optional follow-up (Autocorrect / "change this") inside each screen.
        (
          title: tr(context, 'Build a Website'),
          builder: (_) => const SiteChatBuilderScreen(),
        ),
        (
          title: tr(context, 'App chat builder'),
          builder: (_) => const AppChatBuilderScreen(),
        ),
        (
          title: tr(context, 'Web Dev Lab'),
          builder: (_) => const WebDevLabScreen(),
        ),
        (
          title: tr(context, 'App Dev Lab'),
          builder: (_) => const AppDevLabScreen(),
        ),
        (
          title: tr(context, 'Python Lab'),
          builder: (_) => const PythonLabScreen(),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs(context);
    final ac = AppColors.of(context);

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: ac.surface,
              border: Border(bottom: BorderSide(color: ac.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _LabTabButton(
                      label: tabs[i].title,
                      active: i == _active,
                      onTap: () {
                        // A focused field in the lab being left otherwise
                        // keeps the keyboard up and swallows typing meant
                        // for the newly-shown one.
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() {
                          _active = i;
                          _visited.add(i);
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          // Each lab already accounts for the top status-bar inset in its
          // own AppBar/SafeArea, on the assumption it's the top of the
          // screen — true when pushed as its own route, no longer true now
          // that the tab row above already claimed that space. Without
          // this, a phone shows the same top padding twice.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: IndexedStack(
              index: _active,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _visited.contains(i) ? tabs[i].builder(context) : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabTabButton extends StatelessWidget {
  const _LabTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // One brand treatment for every tab — the app icon itself is a
            // single violet→blue→cyan gradient (see assets/branding), not a
            // different hue per tool, so the highlight matches that rather
            // than reusing the per-mode accent colors (orange/teal/etc.)
            // part 1 asked to remove. The shader only wraps the *active*
            // label — applying it unconditionally would tint the inactive
            // ones too, since ShaderMask doesn't know about that state.
            active
                ? ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.brandGradient.createShader(bounds),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: ac.textSecondary,
                    ),
                  ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 3,
              width: active ? 28 : 0,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat view ─────────────────────────────────────────────────────────────────

class _ChatView extends ConsumerWidget {
  const _ChatView({
    required this.state,
    required this.scrollController,
    required this.messageController,
    required this.onScrollToBottom,
  });

  final _CreateState state;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final VoidCallback onScrollToBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allCount = state.messages.length + (state.isGenerating ? 1 : 0);

    return MaxWidth(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: allCount,
              itemBuilder: (_, i) {
                if (i == state.messages.length) {
                  return const GeneratingIndicator();
                }
                final m = state.messages[i];
                return _Bubble(
                  text: m.text,
                  isUser: m.isUser,
                  streaming: false,
                );
              },
            ),
          ),
          if (state.savedProjectId != null)
            Container(
              color: AppColors.teachColor.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: AppColors.teachColor,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Project saved!',
                    style: TextStyle(
                      color: AppColors.teachColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          _InputBar(
            controller: messageController,
            isLoading: state.isGenerating,
            onSend: (text) {
              messageController.clear();
              ref.read(_createProvider.notifier).send(text);
              onScrollToBottom();
            },
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isUser,
    required this.streaming,
  });
  final String text;
  final bool isUser;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: isUser ? null : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                text.isEmpty ? '…' : text,
                style: TextStyle(
                  color: isUser ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  height: 1.5,
                ),
              ),
            ),
            if (streaming) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool isLoading;
  final void Function(String) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (t) {
                if (t.trim().isNotEmpty) onSend(t.trim());
              },
              decoration: const InputDecoration(
                hintText: 'Reply...',
                border: InputBorder.none,
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          isLoading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : IconButton.filled(
                  onPressed: () {
                    final t = controller.text.trim();
                    if (t.isNotEmpty) onSend(t);
                  },
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
