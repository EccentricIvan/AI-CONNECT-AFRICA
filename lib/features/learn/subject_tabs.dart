import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../notes/note_pdf_screen.dart';
import 'notes_quiz.dart';
import 'subject_notes.dart';

/// A subject's notes as the teacher shared them: the PDF itself, rendered
/// in place, or the note's text when there is no PDF.
class SubjectNotesTab extends ConsumerStatefulWidget {
  const SubjectNotesTab({super.key, required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<SubjectNotesTab> createState() => _SubjectNotesTabState();
}

class _SubjectNotesTabState extends ConsumerState<SubjectNotesTab> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final notesAsync = ref.watch(subjectNotesProvider(widget.subjectId));
    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(tr(context, 'Notes unavailable'))),
      data: (notes) {
        if (notes.isEmpty) {
          return Center(
            child: Text(
              tr(context, 'No notes yet'),
              style: TextStyle(color: ac.textSecondary),
            ),
          );
        }
        final note = notes.firstWhere(
          (n) => n.title == _selected,
          orElse: () => notes.first,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notes.length > 1)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  children: [
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            n.pdf != null
                                ? Icons.picture_as_pdf_outlined
                                : Icons.description_outlined,
                            size: 16,
                          ),
                          label: Text(n.title),
                          selected: n.title == note.title,
                          onSelected: (_) =>
                              setState(() => _selected = n.title),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _NoteBody(key: ValueKey(note.title), note: note),
            ),
          ],
        );
      },
    );
  }
}

class _NoteBody extends ConsumerWidget {
  const _NoteBody({super.key, required this.note});

  final SubjectNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final pdf = note.pdf;
    if (pdf != null && note.pdfOnDevice) {
      final path = ref.watch(notePdfPathProvider(pdf.sha256)).valueOrNull;
      if (path == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Stack(
        children: [
          Positioned.fill(
            child: PdfViewer.file(
              path,
              params: const PdfViewerParams(
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: 'pdf-${pdf.sha256}',
              tooltip: tr(context, 'Full screen'),
              onPressed: () => openNotePdf(context, pdf),
              child: const Icon(Icons.open_in_full_rounded),
            ),
          ),
        ],
      );
    }
    return MaxWidth(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            note.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
          if (pdf != null) ...[
            const SizedBox(height: 4),
            Text(
              tr(context, 'PDF not downloaded'),
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          SelectableText(
            note.text,
            style: TextStyle(fontSize: 15, height: 1.6, color: ac.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Questions written from the subject's notes, answered in place.
class SubjectQuizTab extends ConsumerStatefulWidget {
  const SubjectQuizTab({super.key, required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<SubjectQuizTab> createState() => _SubjectQuizTabState();
}

class _SubjectQuizTabState extends ConsumerState<SubjectQuizTab> {
  String get subjectId => widget.subjectId;

  @override
  void initState() {
    super.initState();
    // Questions written ahead from the notes come up at once, no button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final quiz = ref.read(subjectQuizProvider(subjectId));
      if (quiz.questions.isEmpty && !quiz.generating) {
        ref.read(subjectQuizProvider(subjectId).notifier).startStored();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final quiz = ref.watch(subjectQuizProvider(subjectId));
    final notifier = ref.read(subjectQuizProvider(subjectId).notifier);
    // The quiz and the chat share one engine.
    final chatBusy = ref.watch(
      chatProvider.select((c) => c.valueOrNull?.isGenerating ?? false),
    );

    if (quiz.questions.isEmpty && !quiz.generating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.quiz_outlined, size: 48, color: ac.textSecondary),
            const SizedBox(height: 12),
            if (quiz.error != null) ...[
              Text(
                tr(context, quiz.error!),
                style: TextStyle(color: ac.textSecondary),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: chatBusy ? null : () => notifier.start(),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr(context, 'Start quiz')),
            ),
          ],
        ),
      );
    }

    return MaxWidth(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Row(
            children: [
              Text(
                trFill(context, 'Score {score}/{total}', {
                  'score': '${quiz.score}',
                  'total': '${quiz.answers.length}',
                }),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ac.textPrimary,
                ),
              ),
              const Spacer(),
              if (quiz.generating)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${quiz.questions.length}/${quiz.target}',
                      style: TextStyle(fontSize: 12, color: ac.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < quiz.questions.length; i++)
            _QuestionCard(
              index: i,
              subjectId: subjectId,
              chosen: quiz.answers[i],
            ),
          if (quiz.finished) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: chatBusy ? null : () => notifier.start(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr(context, 'New quiz')),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionCard extends ConsumerWidget {
  const _QuestionCard({
    required this.index,
    required this.subjectId,
    required this.chosen,
  });

  final int index;
  final String subjectId;
  final int? chosen;

  Future<void> _choose(WidgetRef ref, int option, bool correct) async {
    ref.read(subjectQuizProvider(subjectId).notifier).answer(index, option);
    final student = await ref.read(activeStudentProvider.future);
    if (student == null) return;
    await ref
        .read(badgeServiceProvider)
        .onPracticeAnswered(student.id, attempted: 1, correct: correct ? 1 : 0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final q = ref.watch(subjectQuizProvider(subjectId)).questions[index];
    final answered = chosen != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${q.question}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: ac.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            for (var o = 0; o < q.options.length; o++)
              _Option(
                letter: String.fromCharCode(65 + o),
                text: q.options[o],
                state: !answered
                    ? _OptionState.open
                    : o == q.correct
                    ? _OptionState.correct
                    : o == chosen
                    ? _OptionState.wrong
                    : _OptionState.idle,
                onTap: answered ? null : () => _choose(ref, o, o == q.correct),
              ),
            if (answered && q.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                q.explanation,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: ac.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _OptionState { open, idle, correct, wrong }

class _Option extends StatelessWidget {
  const _Option({
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String letter;
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;
    final (border, fill, icon) = switch (state) {
      _OptionState.correct => (
        AppColors.teachColor,
        AppColors.teachColor.withValues(alpha: 0.08),
        Icons.check_circle,
      ),
      _OptionState.wrong => (
        Colors.red,
        Colors.red.withValues(alpha: 0.06),
        Icons.cancel,
      ),
      _ => (divider, Colors.transparent, null),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Text(letter, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
              if (icon != null) Icon(icon, size: 18, color: border),
            ],
          ),
        ),
      ),
    );
  }
}
