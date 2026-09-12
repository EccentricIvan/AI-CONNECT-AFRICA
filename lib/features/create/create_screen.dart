import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

// ── Project types ─────────────────────────────────────────────────────────────

const _projectTypes = [
  _PType('Essay', Icons.article, 'Write a structured essay'),
  _PType('Business Plan', Icons.trending_up, 'Plan a business idea'),
  _PType('Experiment', Icons.science, 'Design a science experiment'),
  _PType('Story', Icons.menu_book, 'Write a creative story'),
  _PType('Code Plan', Icons.code, 'Plan an app or program'),
  _PType('Other', Icons.lightbulb, 'Any creation project'),
];

class _PType {
  const _PType(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;
}

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
  final _topicController = TextEditingController();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _topicController.dispose();
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
      appBar: StudioAppBar(
        title: state.started
            ? '${state.projectType}: ${state.topic}'
            : tr(context, 'Create'),
        subtitle: state.started
            ? tr(context, 'Build step by step with AI')
            : tr(context, 'Turn ideas into projects'),
        icon: Icons.lightbulb_rounded,
        iconColor: const Color(0xFFFF8A3D),
        actions: [
          if (state.started &&
              state.savedProjectId == null &&
              !state.isGenerating)
            StudioHeaderIconButton(
              icon: Icons.save_outlined,
              tooltip: tr(context, 'Save'),
              onTap: () =>
                  ref.read(_createProvider.notifier).saveProject(context),
            ),
          if (state.started)
            StudioHeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: tr(context, 'New project'),
              onTap: () => ref.invalidate(_createProvider),
            ),
        ],
      ),
      body: state.started
          ? _ChatView(
              state: state,
              scrollController: _scrollController,
              messageController: _messageController,
              onScrollToBottom: _scrollToBottom,
            )
          : _SetupView(topicController: _topicController),
    );
  }
}

// ── Setup view ────────────────────────────────────────────────────────────────

class _SetupView extends ConsumerWidget {
  const _SetupView({required this.topicController});
  final TextEditingController topicController;

  static List<({String title, String subtitle, IconData icon, Color color, String route})> _labItems(
    BuildContext context,
  ) =>
      [
        (
          title: tr(context, 'Build a Website'),
          subtitle: tr(
            context,
            'Select features → coding model builds → Preview/Code edit',
          ),
          icon: Icons.language,
          color: AppColors.createColor,
          route: '/sitechat',
        ),
        (
          title: tr(context, 'Build an App'),
          subtitle: tr(
            context,
            'Select features → coding model builds → Preview/Code edit',
          ),
          icon: Icons.phone_android,
          color: AppColors.learnColor,
          route: '/applab',
        ),
        (
          title: tr(context, 'Web Dev Lab'),
          subtitle: tr(context, 'HTML/CSS/JS editor with live preview'),
          icon: Icons.code,
          color: AppColors.practiceColor,
          route: '/weblab',
        ),
        (
          title: tr(context, 'Python Lab'),
          subtitle: tr(
            context,
            'Guided lessons + code simulator (not a full Python runtime)',
          ),
          icon: Icons.terminal,
          color: AppColors.accentDeep,
          route: '/pythonlab',
        ),
        (
          title: tr(context, 'App chat builder'),
          subtitle: tr(context, 'Guided chat → coding model → Preview/Code'),
          icon: Icons.widgets,
          color: AppColors.teachColor,
          route: '/appchat',
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_createProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              tr(context, 'Start Creating'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'Pick a lab and start building something real.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ..._labItems(context).map((lab) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => GoRouter.of(context).push(lab.route),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [lab.color.withValues(alpha: 0.12), lab.color.withValues(alpha: 0.03)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: lab.color.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [lab.color.withValues(alpha: 0.3), lab.color.withValues(alpha: 0.1)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: lab.color.withValues(alpha: 0.2)),
                        ),
                        child: Icon(lab.icon, color: lab.color, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lab.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lab.subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).hintColor),
                    ],
                  ),
                ),
              ),
            )),
            const SizedBox(height: 32),
            Text(
              'Or start your own project',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Tell the AI mentor what you want to build and it will guide you step by step.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _projectTypes.map((t) {
                final selected = state.projectType == t.label;
                return ChoiceChip(
                  label: Text(t.label),
                  avatar: Icon(t.icon, size: 16),
                  selected: selected,
                  onSelected: (_) =>
                      ref.read(_createProvider.notifier).setType(t.label),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: topicController,
              decoration: const InputDecoration(
                hintText: 'What topic? e.g. "climate change"',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: state.projectType.isEmpty
                    ? null
                    : () {
                        final topic = topicController.text.trim();
                        if (topic.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter a topic first')),
                          );
                          return;
                        }
                        final notifier = ref.read(_createProvider.notifier);
                        notifier.setTopic(topic);
                        notifier.start();
                      },
                child: const Text('Start creating'),
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
