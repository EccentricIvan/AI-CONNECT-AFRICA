import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import 'subject_notes.dart';

/// The learner's class notes by subject, from the chat: read a note (PDF
/// or text) or take a quiz written from it.
Future<void> showClassNotesSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _ClassNotesSheet(),
);

class _ClassNotesSheet extends ConsumerWidget {
  const _ClassNotesSheet();

  void _open(BuildContext context, String subjectId, int tab) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/learn/subject/${Uri.encodeComponent(subjectId)}?tab=$tab');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final subjects = ref.watch(learnerNoteSubjectsProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: subjects.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr(context, 'Notes unavailable')),
        ),
        data: (list) => list.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                child: Text(
                  tr(context, 'No notes yet'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ac.textSecondary),
                ),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  for (final (id, name) in list)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(
                        Icons.menu_book_rounded,
                        color: AppColors.primary,
                      ),
                      title: Text(name, overflow: TextOverflow.ellipsis),
                      onTap: () => _open(context, id, 0),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _open(context, id, 0),
                            child: Text(tr(context, 'Notes')),
                          ),
                          TextButton(
                            onPressed: () => _open(context, id, 1),
                            child: Text(tr(context, 'Quiz')),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
