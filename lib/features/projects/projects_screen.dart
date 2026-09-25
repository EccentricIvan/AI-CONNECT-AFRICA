import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_colors.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../services/projects/project_providers.dart';
import '../../shared/widgets/html_preview.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import 'project_actions.dart';
import 'project_files_sheet.dart';
import 'project_preview.dart';

/// Projects: every creation as a real folder, grouped Websites ·
/// Applications · Python · Guided, with copy / cut / paste / rename / delete
/// and export (zip, share, or — on desktop — the real folder for VS Code).
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);
    return studentAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (student) {
        if (student == null) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: StudioAppBar(
              title: tr(context, 'Projects'),
              icon: Icons.folder_rounded,
              iconColor: AppColors.brandCyan,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(context, 'Create a learner profile to save and see projects.'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _ProjectsView(studentId: student.id);
      },
    );
  }
}

class _Clip {
  const _Clip(this.folder, {required this.cut});
  final ProjectFolder folder;
  final bool cut;
}

class _ProjectsView extends ConsumerStatefulWidget {
  const _ProjectsView({required this.studentId});
  final int studentId;

  @override
  ConsumerState<_ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends ConsumerState<_ProjectsView> {
  /// null = All.
  ProjectKind? _tab;
  _Clip? _clip;
  bool _busy = false;

  ProjectStore get _store => ref.read(projectStoreProvider);

  void _refresh() => ref.invalidate(studentProjectFoldersProvider(widget.studentId));

  /// Snackbar whose text is resolved only if the screen is still mounted.
  void _say(String Function(BuildContext c) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text(context))));
  }

  Future<void> _run(Future<void> Function() action, {String? error}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('projects action failed: $e');
      _say((c) => error ?? tr(c, 'Something went wrong. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────

  void _copy(ProjectFolder f) {
    setState(() => _clip = _Clip(f, cut: false));
    _say((c) => trFill(c, 'Copied "{name}". Open a category and tap Paste.', {'name': f.title}));
  }

  void _cut(ProjectFolder f) {
    setState(() => _clip = _Clip(f, cut: true));
    _say((c) => trFill(c, 'Cut "{name}". Open a category and tap Paste.', {'name': f.title}));
  }

  Future<void> _paste() async {
    final clip = _clip;
    if (clip == null) return;
    final target = _tab ?? clip.folder.kind;
    await _run(() async {
      if (clip.cut) {
        if (target == clip.folder.kind) {
          _say((c) => tr(c, 'It is already in this category.'));
        } else {
          await _store.moveToKind(clip.folder, widget.studentId, target);
          _say((c) => trFill(c, 'Moved to {kind}.', {'kind': target.folderName}));
        }
      } else {
        await _store.duplicate(clip.folder, widget.studentId, kind: target);
        _say((c) => trFill(c, 'Pasted a copy into {kind}.', {'kind': target.folderName}));
      }
      if (mounted) setState(() => _clip = null);
    });
  }

  // ── Folder actions ────────────────────────────────────────────────────────

  Future<void> _rename(ProjectFolder f) async {
    final name = await _askText(
      title: tr(context, 'Rename project'),
      initial: f.title,
      confirm: tr(context, 'Rename'),
    );
    if (name == null || name.trim().isEmpty || name.trim() == f.title) return;
    await _run(() async {
      await _store.rename(f, name);
    });
  }

  Future<void> _delete(ProjectFolder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Delete this project?')),
        content: Text(trFill(ctx,
            '"{name}" and all its files will be deleted from this device. Export it first if you want to keep a copy.',
            {'name': f.title})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _store.delete(f);
      if (_clip?.folder.path == f.path && mounted) setState(() => _clip = null);
      _say((c) => tr(c, 'Project deleted.'));
    });
  }

  /// Takes the project out of the app: exported first, then removed here
  /// only once the export really happened.
  Future<void> _moveOut(ProjectFolder f) async {
    bool done;
    if (ProjectStore.foldersAreUserVisible) {
      done = await copyProjectTo(context, ref, f) != null;
    } else {
      done = await exportProjectZip(context, ref, f);
    }
    if (!done) return;
    await _store.delete(f);
    _refresh();
    _say((c) => tr(c, 'Moved out of the app.'));
  }

  Future<String?> _askText({
    required String title,
    required String initial,
    required String confirm,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text), child: Text(confirm)),
        ],
      ),
    );
  }

  void _open(ProjectFolder f) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectDetailScreen(
        folder: f,
        onRename: () => _rename(f),
        onCopy: () => _copy(f),
        onCut: () => _cut(f),
        onDelete: () => _delete(f),
        onMoveOut: () => _moveOut(f),
      ),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(studentProjectFoldersProvider(widget.studentId));
    final all = foldersAsync.valueOrNull ?? const <ProjectFolder>[];
    final shown = _tab == null ? all : all.where((f) => f.kind == _tab).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'Projects'),
        subtitle: tr(context, 'Your creations, as real project folders'),
        icon: Icons.folder_rounded,
        iconColor: AppColors.brandCyan,
        actions: [
          if (ProjectStore.foldersAreUserVisible)
            StudioHeaderIconButton(
              icon: Icons.folder_open_rounded,
              tooltip: tr(context, 'Open the Projects folder'),
              onTap: () async {
                final dir = await _store.learnerDirectory(widget.studentId);
                await showInFileManager(dir.path);
              },
            ),
          StudioHeaderIconButton(
            icon: Icons.refresh_rounded,
            tooltip: tr(context, 'Refresh'),
            onTap: _refresh,
          ),
          StudioHeaderIconButton(
            icon: Icons.add_rounded,
            tooltip: tr(context, 'New project'),
            onTap: () => context.go('/create'),
          ),
        ],
      ),
      body: Column(
        children: [
          _KindTabs(
            active: _tab,
            counts: {
              null: all.length,
              for (final k in ProjectKind.values) k: all.where((f) => f.kind == k).length,
            },
            onChanged: (k) => setState(() => _tab = k),
          ),
          if (_clip != null) _ClipboardBanner(
            clip: _clip!,
            target: _tab,
            onPaste: _paste,
            onCancel: () => setState(() => _clip = null),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: foldersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) {
                if (shown.isEmpty) return _EmptyProjects(kind: _tab);
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: MaxWidth(
                    maxWidth: 960,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final f = shown[i];
                        return _FolderCard(
                          folder: f,
                          highlighted: _clip?.folder.path == f.path,
                          onOpen: () => _open(f),
                          onAction: (a) {
                            switch (a) {
                              case _Action.open:
                                _open(f);
                              case _Action.rename:
                                _rename(f);
                              case _Action.copy:
                                _copy(f);
                              case _Action.cut:
                                _cut(f);
                              case _Action.delete:
                                _delete(f);
                              case _Action.exportZip:
                                exportProjectZip(context, ref, f).then((_) => _refresh());
                              case _Action.share:
                                shareProjectZip(context, ref, f).then((_) => _refresh());
                              case _Action.copyTo:
                                copyProjectTo(context, ref, f).then((_) => _refresh());
                              case _Action.moveOut:
                                _moveOut(f);
                              case _Action.showFolder:
                                showInFileManager(f.path);
                              case _Action.vscode:
                                openInVsCode(context, f.path);
                            }
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tabs ────────────────────────────────────────────────────────────────────

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.active, required this.counts, required this.onChanged});
  final ProjectKind? active;
  final Map<ProjectKind?, int> counts;
  final ValueChanged<ProjectKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final tabs = <(ProjectKind?, String)>[
      (null, tr(context, 'All')),
      (ProjectKind.website, tr(context, 'Websites')),
      (ProjectKind.application, tr(context, 'Applications')),
      (ProjectKind.python, tr(context, 'Python')),
      (ProjectKind.guided, tr(context, 'Guided')),
    ];
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: ac.surface,
        border: Border(bottom: BorderSide(color: ac.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final (kind, label) in tabs)
              _TabButton(
                label: '$label  ${counts[kind] ?? 0}',
                active: active == kind,
                onTap: () => onChanged(kind),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              active
                  ? ShaderMask(
                      shaderCallback: (b) => AppColors.brandGradient.createShader(b),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    )
                  : Text(label,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500, color: ac.textSecondary)),
              const SizedBox(height: 6),
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
      ),
    );
  }
}

class _ClipboardBanner extends StatelessWidget {
  const _ClipboardBanner({
    required this.clip,
    required this.target,
    required this.onPaste,
    required this.onCancel,
  });
  final _Clip clip;
  final ProjectKind? target;
  final VoidCallback onPaste;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final where = (target ?? clip.folder.kind).folderName;
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(clip.cut ? Icons.content_cut_rounded : Icons.content_copy_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              trFill(context, '{action} "{name}"', {
                'action': clip.cut ? tr(context, 'Cut') : tr(context, 'Copied'),
                'name': clip.folder.title,
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onCancel, child: Text(tr(context, 'Cancel'))),
          FilledButton.icon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: Text(trFill(context, 'Paste in {kind}', {'kind': where})),
          ),
        ],
      ),
    );
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

enum _Action {
  open, rename, copy, cut, delete, exportZip, share, copyTo, moveOut, showFolder, vscode,
}

IconData _kindIcon(ProjectKind k) => switch (k) {
      ProjectKind.website => Icons.language_rounded,
      ProjectKind.application => Icons.phone_android_rounded,
      ProjectKind.python => Icons.terminal_rounded,
      ProjectKind.guided => Icons.menu_book_rounded,
    };

Color _kindColor(ProjectKind k) => switch (k) {
      ProjectKind.website => AppColors.technologyColor,
      ProjectKind.application => AppColors.createColor,
      ProjectKind.python => AppColors.practiceColor,
      ProjectKind.guided => AppColors.learnColor,
    };

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _date(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

class _FolderCard extends ConsumerWidget {
  const _FolderCard({
    required this.folder,
    required this.highlighted,
    required this.onOpen,
    required this.onAction,
  });
  final ProjectFolder folder;
  final bool highlighted;
  final VoidCallback onOpen;
  final ValueChanged<_Action> onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final color = _kindColor(folder.kind);
    final m = folder.manifest;
    final desktop = ProjectStore.foldersAreUserVisible;
    final vscode = ref.watch(vsCodeAvailableProvider).valueOrNull ?? false;
    PopupMenuItem<_Action> item(_Action a, IconData icon, String label) => PopupMenuItem(
          value: a,
          child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
        );

    return Material(
      color: ac.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted ? AppColors.primary : ac.border,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_kindIcon(folder.kind), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(folder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, color: ac.textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (m.templateName.isNotEmpty) m.templateName else tr(context, folder.kind.label),
                        trFill(context, '{n} files', {'n': '${folder.fileCount}'}),
                        _size(folder.sizeBytes),
                        _date(m.updatedAt),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: ac.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    if (m.exportedAt != null) _Pill(tr(context, 'Exported'), AppColors.teachColor),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                tooltip: tr(context, 'Project actions'),
                onSelected: onAction,
                itemBuilder: (_) => [
                  item(_Action.open, Icons.visibility_outlined, tr(context, 'Open')),
                  item(_Action.rename, Icons.drive_file_rename_outline, tr(context, 'Rename')),
                  item(_Action.copy, Icons.content_copy_rounded, tr(context, 'Copy')),
                  item(_Action.cut, Icons.content_cut_rounded, tr(context, 'Cut')),
                  const PopupMenuDivider(),
                  if (desktop) ...[
                    item(_Action.copyTo, Icons.drive_folder_upload_outlined, tr(context, 'Copy to a folder…')),
                    item(_Action.showFolder, Icons.folder_open_rounded, tr(context, 'Show in folder')),
                    if (vscode) item(_Action.vscode, Icons.code_rounded, tr(context, 'Open in VS Code')),
                  ],
                  item(_Action.exportZip, Icons.archive_outlined, tr(context, 'Export as .zip')),
                  item(_Action.share, Icons.share_outlined, tr(context, 'Share…')),
                  item(_Action.moveOut, Icons.drive_file_move_outline, tr(context, 'Move out of the app…')),
                  const PopupMenuDivider(),
                  item(_Action.delete, Icons.delete_outline_rounded, tr(context, 'Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.kind});
  final ProjectKind? kind;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.createColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.folder_open, color: AppColors.createColor, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              kind == null
                  ? tr(context, 'No projects yet')
                  : trFill(context, 'No {kind} yet', {'kind': tr(context, kind!.folderName)}),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: ac.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context,
                  'Build a website or an app in Create — each one is saved here, ready to open, share or put online.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: ac.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/create'),
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'Start a project')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────────

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({
    super.key,
    required this.folder,
    required this.onRename,
    required this.onCopy,
    required this.onCut,
    required this.onDelete,
    required this.onMoveOut,
  });

  final ProjectFolder folder;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onDelete;
  final VoidCallback onMoveOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final m = folder.manifest;
    final desktop = ProjectStore.foldersAreUserVisible;
    final vscode = ref.watch(vsCodeAvailableProvider).valueOrNull ?? false;
    final hasPage = File(p.join(folder.path, 'frontend', 'index.html')).existsSync() ||
        File(p.join(folder.path, 'index.html')).existsSync();
    final hasDeploy = File(p.join(folder.path, 'DEPLOY.md')).existsSync();

    void back(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => SizedBox(
          width: 160,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              alignment: Alignment.centerLeft,
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(folder.title, overflow: TextOverflow.ellipsis)),
      body: MaxWidth(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              [
                tr(context, folder.kind.label),
                if (m.templateName.isNotEmpty) m.templateName,
                trFill(context, '{n} files', {'n': '${folder.fileCount}'}),
                _size(folder.sizeBytes),
                trFill(context, 'Updated {date}', {'date': _date(m.updatedAt)}),
              ].join(' · '),
              style: TextStyle(color: ac.textSecondary),
            ),
            const SizedBox(height: 6),
            SelectableText(
              folder.path,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: ac.textSecondary),
            ),
            if (m.features.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in m.features) Chip(label: Text(f), visualDensity: VisualDensity.compact),
              ]),
            ],
            const SizedBox(height: 16),
            if (hasPage)
              SizedBox(
                height: 420,
                child: FutureBuilder<String?>(
                  future: buildProjectPreviewHtml(folder),
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final html = snap.data;
                    if (html == null) return const SizedBox.shrink();
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: ac.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: HtmlPreviewPane(html: html),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Text(tr(context, 'Work with it'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              action(Icons.account_tree_outlined, tr(context, 'Files'),
                  () => showProjectFilesSheet(context, folder)),
              if (hasDeploy)
                action(Icons.rocket_launch_outlined, tr(context, 'How to launch'),
                    () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ProjectGuideScreen(folder: folder, fileName: 'DEPLOY.md'),
                        ))),
              action(Icons.description_outlined, tr(context, 'Read me'),
                  () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProjectGuideScreen(folder: folder, fileName: 'README.md'),
                      ))),
              if (desktop && vscode)
                action(Icons.code_rounded, tr(context, 'Open in VS Code'),
                    () => openInVsCode(context, folder.path)),
              if (desktop)
                action(Icons.folder_open_rounded, tr(context, 'Show in folder'),
                    () => showInFileManager(folder.path)),
            ]),
            const SizedBox(height: 20),
            Text(tr(context, 'Take it elsewhere'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              desktop
                  ? tr(context, 'Copy the folder to your VS Code workspace or a USB stick, or export a .zip.')
                  : tr(context, 'Export a .zip to Downloads or share it, then unzip it on a computer and open the folder in VS Code.'),
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (desktop)
                action(Icons.drive_folder_upload_outlined, tr(context, 'Copy to a folder…'),
                    () => copyProjectTo(context, ref, folder)),
              action(Icons.archive_outlined, tr(context, 'Export as .zip'),
                  () => exportProjectZip(context, ref, folder)),
              action(Icons.share_outlined, tr(context, 'Share…'),
                  () => shareProjectZip(context, ref, folder)),
              action(Icons.drive_file_move_outline, tr(context, 'Move out of the app…'),
                  () => back(onMoveOut)),
            ]),
            const SizedBox(height: 20),
            Text(tr(context, 'Organise'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              action(Icons.drive_file_rename_outline, tr(context, 'Rename'), () => back(onRename)),
              action(Icons.content_copy_rounded, tr(context, 'Copy'), () => back(onCopy)),
              action(Icons.content_cut_rounded, tr(context, 'Cut'), () => back(onCut)),
              action(Icons.delete_outline_rounded, tr(context, 'Delete'), () => back(onDelete),
                  color: Colors.red.shade700),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Renders a project's DEPLOY.md / README.md — offline text, links are
/// selectable so they can be typed in later when there is a connection.
class ProjectGuideScreen extends StatelessWidget {
  const ProjectGuideScreen({super.key, required this.folder, required this.fileName});
  final ProjectFolder folder;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final file = File(p.join(folder.path, fileName));
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName == 'DEPLOY.md' ? tr(context, 'How to launch') : tr(context, 'Read me')),
        actions: [
          IconButton(
            tooltip: tr(context, 'Copy'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              if (!await file.exists()) return;
              final text = await file.readAsString();
              if (context.mounted) await copyTextToClipboard(context, text);
            },
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: file.exists().then((ok) => ok ? file.readAsString() : ''),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) {
            return Center(child: Text(tr(context, 'This project has no guide file.')));
          }
          return MaxWidth(
            maxWidth: 820,
            child: Markdown(
              data: snap.data!,
              selectable: true,
              padding: const EdgeInsets.all(20),
            ),
          );
        },
      ),
    );
  }
}
