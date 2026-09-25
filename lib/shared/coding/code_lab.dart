import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../features/settings/coder_package_prompt.dart';
import '../../l10n/app_locale.dart';
import '../widgets/code_autocorrect_button.dart';
import '../widgets/code_instruction_bar.dart';
import '../widgets/html_preview.dart';
import 'code_autocorrect.dart';
import 'code_instruction_edit.dart';
import 'code_lab_session.dart';
import '../../features/projects/scaffold/project_scaffold.dart';
import '../../features/projects/widgets/save_lab_to_projects.dart';
import '../../services/projects/project_manifest.dart';

/// One step of a guided lab: what to read, what to type, what to try next.
class CodeLabLesson {
  const CodeLabLesson({
    required this.title,
    required this.instruction,
    required this.starterCode,
    this.hint,
    this.challenge,
  });

  final String title;
  final String instruction;

  /// Complete HTML the student starts from. Always a full document with a
  /// charset — the preview loads it from a `file://` URL, where a browser
  /// with no declared encoding falls back to the OS codepage and turns any
  /// non-ASCII character into mojibake.
  final String starterCode;

  final String? hint;
  final String? challenge;
}

/// The shared Lab workspace: lesson text, a code editor, and the page that
/// code produces — RUN moves to the preview tab.
///
/// Both labs run on this one widget so Web and App Dev stay the same product:
/// the student writes code and a real browser engine paints exactly that code.
/// The coding model is never on the path between typing and seeing; it is only
/// reachable through Autocorrect, as an explicit, optional step.
class CodeLabScaffold extends ConsumerStatefulWidget {
  const CodeLabScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.lessons,
    required this.sessionId,
    this.editorHint,
    this.projectKind = ProjectKind.website,
  });

  final String title;
  final IconData icon;
  final List<CodeLabLesson> lessons;

  /// Key this lab's saved work is stored under — see [CodeLabSections].
  final String sessionId;

  final String? editorHint;

  /// Projects folder "Save to Projects" writes this lab's page into.
  final ProjectKind projectKind;

  @override
  ConsumerState<CodeLabScaffold> createState() => _CodeLabScaffoldState();
}

class _CodeLabScaffoldState extends ConsumerState<CodeLabScaffold>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();
  String _previewHtml = '';
  int _currentLesson = 0;
  bool _showHint = false;
  bool _autocorrectBusy = false;
  bool _instructionBusy = false;
  String? _undoSnapshot;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Pick up where the student left off. A saved lesson index is clamped:
    // the labs have different lesson counts, and a stale index from an older
    // build must not crash the screen.
    final saved = ref.read(codeLabSessionProvider.notifier).read(
          widget.sessionId,
        );
    if (saved != null && !saved.isEmpty) {
      _currentLesson = saved.lessonIndex.clamp(0, widget.lessons.length - 1);
      _codeController.text = saved.code;
      _previewHtml = saved.result;
      _tabController.index = saved.tab.clamp(0, 1);
    } else {
      _codeController.text = widget.lessons.first.starterCode;
    }

    _codeController.addListener(_persistCode);
    _tabController.addListener(_persistTab);
  }

  @override
  void dispose() {
    _codeController.removeListener(_persistCode);
    _tabController.removeListener(_persistTab);
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Nothing here watches [codeLabSessionProvider], so writing to it costs a
  /// map copy and rebuilds nothing.
  void _persistCode() => ref
      .read(codeLabSessionProvider.notifier)
      .update(widget.sessionId, code: _codeController.text);

  void _persistTab() {
    if (_tabController.indexIsChanging) return;
    ref
        .read(codeLabSessionProvider.notifier)
        .update(widget.sessionId, tab: _tabController.index);
  }

  void _runCode() {
    setState(() => _previewHtml = _codeController.text);
    ref.read(codeLabSessionProvider.notifier).update(
          widget.sessionId,
          code: _codeController.text,
          result: _previewHtml,
          lessonIndex: _currentLesson,
          hasRun: true,
        );
    _tabController.animateTo(1);
  }

  /// "Tell AI what to change" — a plain-English restyle applied to the code
  /// already in the editor. The model returns a small CSS patch, never a
  /// rewrite, so a poor reply can restyle the page but cannot destroy it, and
  /// [_undoSnapshot] puts it back either way.
  Future<void> _applyInstruction(String instruction) async {
    if (_instructionBusy) return;
    final before = _codeController.text;
    if (before.trim().isEmpty) return;
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;
    setState(() => _instructionBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final fixed = await applyCodeInstruction(
        source: before,
        instruction: instruction,
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      if (!mounted) return;
      if (fixed == null) {
        showInstructionNoticeSnack(
          context,
          tr(context, "Couldn't apply that — try describing it a different way."),
        );
        return;
      }
      _undoSnapshot = before;
      _codeController.text = fixed;
      setState(() => _previewHtml = fixed);
      _tabController.animateTo(1);
      if (!mounted) return;
      showInstructionAppliedSnack(context, onUndo: _undoLastInstruction);
    } catch (_) {
      if (!mounted) return;
      showInstructionNoticeSnack(
        context,
        tr(context, 'Something went wrong. Please try again.'),
      );
    } finally {
      if (mounted) setState(() => _instructionBusy = false);
    }
  }

  void _undoLastInstruction() {
    final previous = _undoSnapshot;
    if (previous == null) return;
    _undoSnapshot = null;
    _codeController.text = previous;
    setState(() => _previewHtml = previous);
  }

  Future<void> _autocorrect() async {
    if (_autocorrectBusy) return;
    final before = _codeController.text;
    if (before.trim().isEmpty) return;
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;
    setState(() => _autocorrectBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final fixed = await autocorrectCode(
        source: before,
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      if (!mounted) return;
      if (fixed != before) {
        _codeController.value = TextEditingValue(
          text: fixed,
          selection: TextSelection.collapsed(offset: fixed.length),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Autocorrect applied'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'No changes needed'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      final fixed = applyHeuristicAutocorrect(
        before,
        CodeAutocorrectKind.html,
      );
      _codeController.text = fixed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Applied quick local fixes'))),
      );
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  void _loadLesson(int index) {
    setState(() {
      _currentLesson = index;
      _showHint = false;
      _undoSnapshot = null;
      _codeController.text = widget.lessons[index].starterCode;
    });
    ref.read(codeLabSessionProvider.notifier).update(
          widget.sessionId,
          lessonIndex: index,
          code: _codeController.text,
        );
    _tabController.animateTo(0);
  }

  void _nextLesson() {
    if (_currentLesson < widget.lessons.length - 1) {
      _loadLesson(_currentLesson + 1);
    }
  }

  void _prevLesson() {
    if (_currentLesson > 0) _loadLesson(_currentLesson - 1);
  }

  /// Folder this lab's work was saved into (Projects), once saved.
  String? _projectId;
  String? _projectTitle;

  Future<void> _saveToProjects() async {
    final html = _codeController.text;
    if (html.trim().isEmpty) return;
    final saved = await saveLabToProjects(
      context,
      ref,
      kind: widget.projectKind,
      suggestedTitle: widget.lessons[_currentLesson].title.replaceFirst(RegExp(r'^Lesson \d+:\s*'), ''),
      source: widget.sessionId,
      projectId: _projectId,
      currentTitle: _projectTitle,
      buildFiles: (title, images) =>
          buildStaticWebProject(title: title, html: html, images: images),
    );
    if (saved != null && mounted) {
      setState(() {
        _projectId = saved.id;
        _projectTitle = saved.title;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lessons[_currentLesson];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(widget.icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr(context, widget.title)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: tr(context, 'Save to Projects'),
            onPressed: _saveToProjects,
          ),
          CodeAutocorrectButton(
            busy: _autocorrectBusy,
            onPressed: _autocorrect,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: tr(context, 'All lessons'),
            onPressed: () => _showLessonPicker(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.code), text: tr(context, 'Code')),
            Tab(
              icon: const Icon(Icons.visibility),
              text: tr(context, 'Preview'),
            ),
          ],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _runCode,
        icon: const Icon(Icons.play_arrow),
        label: Text(tr(context, 'RUN')),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              _InstructionBar(
                lesson: lesson,
                lessonIndex: _currentLesson,
                totalLessons: widget.lessons.length,
                showHint: _showHint,
                onToggleHint: () => setState(() => _showHint = !_showHint),
                onNext: _currentLesson < widget.lessons.length - 1
                    ? _nextLesson
                    : null,
                onPrev: _currentLesson > 0 ? _prevLesson : null,
              ),
              Expanded(
                child: _CodeEditor(
                  controller: _codeController,
                  hint: widget.editorHint,
                ),
              ),
              // Same "Tell AI what to change" bar the chat builders carry, so
              // a student never has to learn a second way to ask for help.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: CodeInstructionBar(
                    busy: _instructionBusy,
                    onSubmit: _applyInstruction,
                  ),
                ),
              ),
            ],
          ),
          _Preview(html: _previewHtml),
        ],
      ),
    );
  }

  void _showLessonPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: widget.lessons.length,
        itemBuilder: (_, i) {
          final l = widget.lessons[i];
          final isCurrent = i == _currentLesson;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isCurrent
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: isCurrent
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              l.title,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              l.instruction,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.pop(ctx);
              _loadLesson(i);
            },
          );
        },
      ),
    );
  }
}

// ── Instruction bar ──────────────────────────────────────────────────────────

class _InstructionBar extends StatelessWidget {
  const _InstructionBar({
    required this.lesson,
    required this.lessonIndex,
    required this.totalLessons,
    required this.showHint,
    required this.onToggleHint,
    required this.onNext,
    required this.onPrev,
  });

  final CodeLabLesson lesson;
  final int lessonIndex;
  final int totalLessons;
  final bool showHint;
  final VoidCallback onToggleHint;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lesson.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Text(
                  '${lessonIndex + 1}/$totalLessons',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              lesson.instruction,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (showHint && lesson.hint != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb, size: 14, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'Hint',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lesson.hint!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (lesson.challenge != null) ...[
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(
                          Icons.emoji_events,
                          size: 14,
                          color: AppColors.createColor,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Challenge',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.createColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lesson.challenge!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                if (onPrev != null)
                  _SmallButton(
                    icon: Icons.arrow_back,
                    label: 'Prev',
                    onTap: onPrev!,
                  ),
                if (onPrev != null) const SizedBox(width: 8),
                _SmallButton(
                  icon: showHint ? Icons.lightbulb : Icons.lightbulb_outline,
                  label: showHint ? 'Hide Hint' : 'Hint',
                  onTap: onToggleHint,
                ),
                const Spacer(),
                if (onNext != null)
                  _SmallButton(
                    icon: Icons.arrow_forward,
                    label: 'Next Lesson',
                    onTap: onNext!,
                    primary: true,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: primary
              ? AppColors.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: primary
              ? null
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: primary
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primary
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Code editor ──────────────────────────────────────────────────────────────

class _CodeEditor extends StatelessWidget {
  const _CodeEditor({required this.controller, this.hint});

  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E2E),
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFFCDD6F4),
          height: 1.5,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          hintText: hint ?? 'Write your HTML, CSS, and JavaScript here...',
          hintStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Color(0xFF585B70),
          ),
        ),
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
      ),
    );
  }
}

// ── Preview ──────────────────────────────────────────────────────────────────

class _Preview extends StatelessWidget {
  const _Preview({required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.web, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(
              'Tap RUN to see your page',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: BrowserFrame(html: html, showSourceToggle: false),
    );
  }
}
