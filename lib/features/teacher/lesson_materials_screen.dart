import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../db/daos/topic_resource_dao.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../services/custom_subject_service.dart';
import '../../services/offline_storage_service.dart';
import '../../services/resource_import_service.dart';
import '../../services/resource_text_extractor.dart';
import '../../shared/widgets/studio_page.dart';
import 'class_providers.dart';
import 'resource_labels.dart';

/// Where a teacher creates subjects and adds the material they teach from.
///
/// Everything a teacher sees here is a subject, a note and a term. The storage
/// engine, the chunking, and the retrieval index are never named — see
/// [ResourceLabels], which holds every string on this screen and is asserted
/// against [kForbiddenTechnicalTerms] in the tests.
class LessonMaterialsScreen extends ConsumerWidget {
  const LessonMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(customSubjectsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, ResourceLabels.workspace),
        subtitle: tr(context, ResourceLabels.workspaceSubtitle),
        icon: Icons.folder_copy_rounded,
        iconColor: AppColors.accentBlue,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSubject(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr(context, ResourceLabels.newSubject)),
      ),
      body: subjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (subjects) {
          if (subjects.isEmpty) {
            return _EmptyState(
              title: tr(context, ResourceLabels.noSubjects),
              hint: tr(context, ResourceLabels.noSubjectsHint),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
            children: [
              StudioSectionHeader(
                title: tr(context, ResourceLabels.mySubjects),
              ),
              const SizedBox(height: 12),
              for (final s in subjects)
                _SubjectTile(subject: s, key: ValueKey(s.subjectId)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createSubject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, ResourceLabels.newSubject)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr(ctx, ResourceLabels.subjectName),
            hintText: tr(ctx, ResourceLabels.subjectNameHint),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, ResourceLabels.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(tr(ctx, ResourceLabels.createSubject)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;

    final result = await ref
        .read(customSubjectServiceProvider)
        .create(name: name);
    if (!context.mounted) return;

    if (!result.ok) {
      _toast(context, result.error ?? '');
      return;
    }
    ref.invalidate(customSubjectsProvider);
    ref.invalidate(mergedSubjectsProvider);
    _toast(context, tr(context, ResourceLabels.subjectCreated));
  }
}

// ── One subject, with its material ───────────────────────────────────────

class _SubjectTile extends ConsumerWidget {
  const _SubjectTile({required this.subject, super.key});

  final CustomSubject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(topicResourcesProvider(subject.subjectId));
    final shares =
        ref.watch(noteSharesProvider(subject.subjectId)).valueOrNull ??
        const {};
    // Where this subject's notes may go: classes this device owns, plus
    // classes it co-teaches *this* subject in.
    final classes = <({String uuid, String label})>[
      for (final c
          in ref.watch(ownedClassesProvider).valueOrNull ?? const <ClassGroup>[])
        (uuid: c.groupUuid!, label: classLabel(c)),
      for (final d
          in ref.watch(delegatedClassesProvider).valueOrNull ??
              const <CoTeachingClass>[])
        if (delegatedSubjects(d).contains(subject.subjectId))
          (uuid: d.classGroupUuid, label: delegatedClassLabel(d)),
    ];
    final classNames = <String?, String>{
      for (final c in classes) c.uuid: c.label,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.menu_book_rounded),
        title: Text(
          subject.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: resources.maybeWhen(
          data: (list) => Text(
            list.isEmpty
                ? tr(context, ResourceLabels.noResources)
                : '${list.length}',
          ),
          orElse: () => null,
        ),
        children: [
          resources.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) =>
                Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
            data: (list) => Column(
              children: [
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      tr(context, ResourceLabels.noResourcesHint),
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                for (final r in list)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined, size: 20),
                    title: Text(r.resourceTitle),
                    subtitle: Text(
                      '${ResourceLabels.termLabel(context, r.termMarker)} · '
                      '${_sharedWith(context, shares[r.resourceTitle], classNames)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: tr(context, 'Share with classes'),
                          icon: Icon(
                            (shares[r.resourceTitle] ?? const {}).isEmpty
                                ? Icons.group_add_outlined
                                : Icons.groups_rounded,
                          ),
                          onPressed: () => _share(
                            context,
                            ref,
                            r,
                            classes,
                            shares[r.resourceTitle] ?? const {},
                          ),
                        ),
                        IconButton(
                          tooltip: tr(context, ResourceLabels.removeResource),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(context, ref, r),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _addFromFile(context, ref),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(tr(context, ResourceLabels.uploadFile)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addTyped(context, ref),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(tr(context, ResourceLabels.typeNotes)),
                ),
                TextButton.icon(
                  onPressed: () => _removeSubject(context, ref),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: Text(tr(context, ResourceLabels.removeSubject)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              tr(context, ResourceLabels.uploadHint),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(topicResourcesProvider(subject.subjectId));
    ref.invalidate(customSubjectsProvider);
    ref.invalidate(mergedSubjectsProvider);
    ref.invalidate(subjectByIdProvider(subject.subjectId));
  }

  Future<void> _addFromFile(BuildContext context, WidgetRef ref) async {
    final term = await _askTerm(context);
    if (term == null || !context.mounted) return;

    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: tr(context, ResourceLabels.uploadFile),
      type: FileType.custom,
      allowedExtensions: kSupportedResourceExtensions,
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;

    final progress = ValueNotifier<(int, int)>((0, 0));
    final cancelling = ValueNotifier<bool>(false);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ReadingDialog(progress: progress, cancelling: cancelling),
      ),
    );

    final ImportReport report;
    try {
      report = await ref
          .read(resourceImportServiceProvider)
          .importFile(
            path: path,
            subjectId: subject.subjectId,
            termMarker: term,
            onProgress: (done, total) =>
                progress.value = (done < total ? done + 1 : total, total),
            isCancelled: () => cancelling.value,
          );
    } finally {
      navigator.pop();
      progress.dispose();
      cancelling.dispose();
    }
    if (!context.mounted) return;

    if (!report.ok) {
      if (report.cancelled) {
        _toast(context, report.failure ?? '');
      } else {
        _showFailure(context, report.failure ?? '');
      }
      return;
    }
    _refresh(ref);
    // Name the file the teacher added — never how it was split inside.
    final details = [
      if (report.ocrPages > 0)
        trFill(context, ResourceLabels.pagesScanned, {'count': '${report.ocrPages}'}),
      if (report.diagramCount > 0)
        trFill(context, ResourceLabels.diagramsMarked, {'count': '${report.diagramCount}'}),
      if (report.unreadablePages > 0)
        trFill(context, ResourceLabels.pagesUnreadable, {'count': '${report.unreadablePages}'}),
    ];
    _toast(
      context,
      [
        trFill(context, ResourceLabels.fileAdded, {'title': report.documentTitle}),
        ...details,
      ].join(' · '),
    );
  }

  Future<void> _addTyped(BuildContext context, WidgetRef ref) async {
    final titleCtl = TextEditingController();
    final bodyCtl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, ResourceLabels.addNote)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr(ctx, ResourceLabels.noteTitle),
                  hintText: tr(ctx, ResourceLabels.noteTitleHint),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtl,
                minLines: 5,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: tr(ctx, ResourceLabels.noteContent),
                  hintText: tr(ctx, ResourceLabels.noteContentHint),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, ResourceLabels.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, ResourceLabels.saveNote)),
          ),
        ],
      ),
    );

    final title = titleCtl.text;
    final body = bodyCtl.text;
    titleCtl.dispose();
    bodyCtl.dispose();
    if (saved != true || !context.mounted) return;

    final term = await _askTerm(context);
    if (term == null || !context.mounted) return;

    final report = await ref
        .read(resourceImportServiceProvider)
        .importText(
          title: title,
          content: body,
          subjectId: subject.subjectId,
          termMarker: term,
        );
    if (!context.mounted) return;

    if (!report.ok) {
      _showFailure(context, report.failure ?? '');
      return;
    }
    _refresh(ref);
    _toast(context, tr(context, ResourceLabels.noteSaved));
  }

  String _sharedWith(
    BuildContext context,
    Set<String>? uuids,
    Map<String?, String> classNames,
  ) {
    final names = [
      for (final u in uuids ?? const <String>{})
        if (classNames[u] != null) classNames[u]!,
    ]..sort();
    return names.isEmpty
        ? tr(context, 'Not shared with any class')
        : trFill(context, 'Shared with {classes}', {
            'classes': names.join(', '),
          });
  }

  /// Which classes/streams receive this note when they sync. Only this
  /// subject's note goes, only to the ticked classes.
  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    ResourceSummary resource,
    List<({String uuid, String label})> classes,
    Set<String> current,
  ) async {
    if (classes.isEmpty) {
      _toast(
        context,
        tr(context, 'Create a class first (Teacher → Add class).'),
      );
      return;
    }
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final picked = {...current};
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(
              trFill(ctx, 'Share “{title}” with', {
                'title': resource.resourceTitle,
              }),
            ),
            content: SizedBox(
              width: 380,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in classes)
                    CheckboxListTile(
                      value: picked.contains(c.uuid),
                      title: Text(c.label),
                      onChanged: (on) => setState(
                        () => on == true
                            ? picked.add(c.uuid)
                            : picked.remove(c.uuid),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      tr(
                        ctx,
                        'Only learners who joined a ticked class get this note, '
                        'and only for this subject.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).hintColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr(ctx, ResourceLabels.cancel)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, picked),
                child: Text(tr(ctx, 'Save')),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return;
    await ref
        .read(dbProvider)
        .classSyncDao
        .setShares(
          subjectId: subject.subjectId,
          documentTitle: resource.resourceTitle,
          classUuids: chosen,
        );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ResourceSummary resource,
  ) async {
    final confirmed = await _confirm(
      context,
      tr(context, ResourceLabels.removeConfirm),
      tr(context, ResourceLabels.removeResource),
    );
    if (!confirmed || !context.mounted) return;

    final removed = await ref
        .read(offlineStorageServiceProvider)
        .deleteTopicResourceByTitle(
          resource.resourceTitle,
          subjectId: subject.subjectId,
        );
    if (!context.mounted) return;

    _refresh(ref);
    _toast(
      context,
      tr(
        context,
        removed > 0
            ? ResourceLabels.noteRemoved
            : ResourceLabels.nothingToRemove,
      ),
    );
  }

  Future<void> _removeSubject(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      tr(context, ResourceLabels.removeSubjectConfirm),
      tr(context, ResourceLabels.removeSubject),
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(customSubjectServiceProvider).delete(subject.subjectId);
    if (!context.mounted) return;

    _refresh(ref);
    _toast(context, tr(context, ResourceLabels.subjectRemoved));
  }

  /// Which term this material belongs to — the Term Core Tracker.
  Future<int?> _askTerm(BuildContext context) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr(ctx, ResourceLabels.termTracker)),
        children: [
          for (final marker in ResourceLabels.termOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, marker),
              child: Text(ResourceLabels.termLabel(ctx, marker)),
            ),
        ],
      ),
    );
  }
}

// ── Small shared pieces ──────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  if (message.isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

/// Page-by-page progress while a file is read; a scanned book takes minutes.
class _ReadingDialog extends StatelessWidget {
  const _ReadingDialog({required this.progress, required this.cancelling});

  final ValueNotifier<(int, int)> progress;
  final ValueNotifier<bool> cancelling;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(tr(context, ResourceLabels.reading)),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, value, _) {
            final (page, total) = value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: total == 0 ? null : page / total),
                if (total > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    trFill(context, ResourceLabels.readingPage, {
                      'page': '$page',
                      'total': '$total',
                    }),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: cancelling,
            builder: (context, stopping, _) => TextButton(
              onPressed: stopping ? null : () => cancelling.value = true,
              child: Text(
                tr(context, stopping ? ResourceLabels.cancelling : ResourceLabels.cancel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failure a teacher needs to read and act on, so it gets a dialog rather
/// than a snack bar that disappears while they are still reading it.
void _showFailure(BuildContext context, String reason) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.error_outline),
      title: Text(tr(ctx, ResourceLabels.readFailed)),
      content: Text(reason),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(
  BuildContext context,
  String message,
  String confirmLabel,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(ctx, ResourceLabels.cancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
