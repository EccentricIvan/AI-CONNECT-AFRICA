import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../services/notes/note_pdf_store.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../learn/subject_notes.dart';
import 'note_access.dart';
import 'note_pdf_screen.dart';

/// One subject's PDFs in My notes, and whether each file is on the device.
class MyNotesSubject {
  const MyNotesSubject(this.id, this.name, this.pdfs);

  final String id;
  final String name;
  final List<(NotePdf, bool)> pdfs;
}

/// The teacher's PDFs for every subject the active learner registered for
/// (all subjects on the teacher's own device). Read-only.
final myNotesProvider = FutureProvider.autoDispose<List<MyNotesSubject>>((
  ref,
) async {
  final readable = await ref.watch(readableNoteSubjectsProvider.future);
  final classUuid = await ref.watch(learnerClassUuidProvider.future);
  final subjects = await ref.watch(learnerNoteSubjectsProvider.future);
  final store = ref.watch(notePdfStoreProvider);
  final pdfs = await store.visibleTo(classUuid);
  return [
    for (final (id, name) in subjects)
      if (canReadNotes(readable, id))
        MyNotesSubject(id, name, [
          for (final p in pdfs)
            if (p.subjectId == id) (p, await store.has(p.sha256)),
        ]),
  ].where((s) => s.pdfs.isNotEmpty).toList();
});

class MyNotesScreen extends ConsumerWidget {
  const MyNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final notes = ref.watch(myNotesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'My notes'),
        icon: Icons.picture_as_pdf_rounded,
        iconColor: AppColors.accentOrange,
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(tr(context, 'Notes unavailable'))),
        data: (subjects) => subjects.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(context, 'No notes for your subjects'),
                      style: TextStyle(color: ac.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => context.push('/class-sync'),
                      child: Text(tr(context, 'My subjects')),
                    ),
                  ],
                ),
              )
            : MaxWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final s in subjects) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text(
                          s.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ac.textPrimary,
                          ),
                        ),
                      ),
                      StudioCard(
                        padding: EdgeInsets.zero,
                        child: Material(
                          type: MaterialType.transparency,
                          child: Column(
                            children: [
                              for (final (pdf, here) in s.pdfs)
                                ListTile(
                                  leading: Icon(
                                    Icons.picture_as_pdf_outlined,
                                    color: here
                                        ? AppColors.accentOrange
                                        : ac.textHint,
                                  ),
                                  title: Text(pdf.documentTitle),
                                  subtitle: Text(
                                    here
                                        ? trFill(context, '{n} pages', {
                                            'n': '${pdf.pages}',
                                          })
                                        : tr(context, 'Not downloaded yet'),
                                  ),
                                  trailing: here
                                      ? const Icon(Icons.chevron_right_rounded)
                                      : null,
                                  enabled: here,
                                  onTap: () => openNotePdf(context, pdf),
                                ),
                            ],
                          ),
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
