import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_provider.dart';
import '../../curriculum/curriculum_models.dart';
import '../../curriculum/lesson_progress.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/quiz_ai_answer.dart';
import '../../shared/widgets/studio_page.dart';

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({
    super.key,
    required this.subjectId,
    required this.unitIndex,
    required this.lessonIndex,
  });

  final String subjectId;
  final int unitIndex;
  final int lessonIndex;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  bool _showQuiz = false;
  bool _lessonMarkedDone = false;
  String _badgeEarned = '';
  final Map<int, int?> _answers = {};
  final Map<int, bool?> _results = {};

  void _checkCompletion(int totalQuestions) async {
    if (_lessonMarkedDone) return;
    if (_results.length < totalQuestions) return;

    final correct = _results.values.where((r) => r == true).length;
    final percent = correct / totalQuestions;

    // Mark complete if 60%+ correct
    if (percent >= 0.6) {
      _lessonMarkedDone = true;
      final progress = ref.read(lessonProgressProvider);
      await progress.markComplete(widget.subjectId, widget.unitIndex, widget.lessonIndex);

      // Award badges
      final student = await ref.read(activeStudentProvider.future);
      if (student != null) {
        final badgeService = ref.read(badgeServiceProvider);
        final badges = await badgeService.onPracticeAnswered(
              student.id,
              attempted: totalQuestions,
              correct: correct,
            );
        // Per-student, so a shared device never credits one learner's
        // lesson to another — see LessonProgress.markCompleteFor.
        final firstTime = await progress.markCompleteFor(
            student.id, widget.subjectId, widget.unitIndex, widget.lessonIndex);
        if (firstTime) {
          badges.addAll(await badgeService.onCurriculumLessonCompleted(student.id));
        }
        if (mounted && badges.isNotEmpty) {
          setState(() => _badgeEarned = badges.first.name);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final curriculum = ref.watch(curriculumServiceProvider);

    return FutureBuilder(
      future: curriculum.load(widget.subjectId),
      builder: (context, snapshot) {
        final subject = snapshot.data;
        if (subject == null) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: StudioAppBar(
              title: tr(context, 'Loading…'),
              showBack: true,
              showMenu: false,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final unit = subject.units[widget.unitIndex];
        final lesson = unit.lessons[widget.lessonIndex];
        final hasNext = widget.lessonIndex < unit.lessons.length - 1;
        final hasPrev = widget.lessonIndex > 0;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: StudioAppBar(
            title: 'Unit ${widget.unitIndex + 1}, Lesson ${widget.lessonIndex + 1}',
            subtitle: unit.title,
            showBack: true,
            showMenu: false,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  lesson.title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),

                // Content
                Text(
                  lesson.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),

                // Diagram
                if (lesson.diagram != null) ...[
                  const _SectionTitle(icon: Icons.schema, title: 'Diagram', color: AppColors.practiceColor),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      lesson.diagram!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFA6E3A1),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Examples
                if (lesson.examples.isNotEmpty) ...[
                  const _SectionTitle(icon: Icons.lightbulb, title: 'Examples', color: AppColors.createColor),
                  const SizedBox(height: 8),
                  ...lesson.examples.map((ex) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.createColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.createColor.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        ex,
                        style: TextStyle(fontSize: 13, height: 1.5, color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  )),
                  const SizedBox(height: 20),
                ],

                // Key Terms
                if (lesson.keyTerms.isNotEmpty) ...[
                  const _SectionTitle(icon: Icons.bookmark, title: 'Key Terms', color: AppColors.primary),
                  const SizedBox(height: 8),
                  ...lesson.keyTerms.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.value,
                            style: TextStyle(fontSize: 13, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),
                ],

                // Quiz toggle
                if (lesson.quiz.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => setState(() {
                        _showQuiz = !_showQuiz;
                        if (!_showQuiz) {
                          _answers.clear();
                          _results.clear();
                        }
                      }),
                      icon: Icon(_showQuiz ? Icons.close : Icons.quiz),
                      label: Text(_showQuiz ? 'Hide Quiz' : 'Test Yourself (${lesson.quiz.length} questions)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.practiceColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Quiz
                if (_showQuiz && lesson.quiz.isNotEmpty) ...[
                  ...lesson.quiz.asMap().entries.map((entry) {
                    final qi = entry.key;
                    final q = entry.value;
                    return _QuizCard(
                      index: qi,
                      question: q,
                      selectedAnswer: _answers[qi],
                      isCorrect: _results[qi],
                      onAnswer: (answerIndex) {
                        setState(() {
                          _answers[qi] = answerIndex;
                          _results[qi] = answerIndex == q.correct;
                        });
                        _checkCompletion(lesson.quiz.length);
                      },
                    );
                  }),
                  // Score
                  if (_results.length == lesson.quiz.length) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.teachColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.teachColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_results.values.where((r) => r == true).length}/${lesson.quiz.length}',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.teachColor),
                          ),
                          Text(
                            _results.values.every((r) => r == true)
                                ? 'Perfect!'
                                : _lessonMarkedDone
                                    ? 'Lesson Complete!'
                                    : 'Need 60% to pass — try again!',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.teachColor),
                          ),
                          if (_lessonMarkedDone) ...[
                            const SizedBox(height: 8),
                            const Icon(Icons.check_circle, color: AppColors.teachColor, size: 28),
                          ],
                          if (_badgeEarned.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('🏅 Badge: $_badgeEarned', style: const TextStyle(fontSize: 13, color: AppColors.primary)),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],

                // Ask AI
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      '/chat?topic=${Uri.encodeComponent(lesson.title)}'
                      '&subject=${Uri.encodeComponent(widget.subjectId)}',
                    ),
                    icon: const Icon(Icons.psychology, size: 18),
                    label: Text(tr(context, 'Ask AI about this lesson')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Navigation
                Row(
                  children: [
                    if (hasPrev)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            context.go(
                              '/learn/subject/${widget.subjectId}/lesson/${widget.unitIndex}/${widget.lessonIndex - 1}',
                            );
                          },
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: Text(tr(context, 'Previous')),
                        ),
                      ),
                    if (hasPrev && hasNext) const SizedBox(width: 12),
                    if (hasNext)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            context.go(
                              '/learn/subject/${widget.subjectId}/lesson/${widget.unitIndex}/${widget.lessonIndex + 1}',
                            );
                          },
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(tr(context, 'Next')),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, required this.color});
  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.index,
    required this.question,
    required this.selectedAnswer,
    required this.isCorrect,
    required this.onAnswer,
  });

  final int index;
  final QuizQuestion question;
  final int? selectedAnswer;
  final bool? isCorrect;
  final void Function(int) onAnswer;

  @override
  Widget build(BuildContext context) {
    final answered = selectedAnswer != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q${index + 1}. ${question.question}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          QuizAiAnswer(key: ValueKey('lesson-$index-${question.question}'), question: question),
          const SizedBox(height: 12),
          ...question.options.asMap().entries.map((entry) {
            final oi = entry.key;
            final option = entry.value;
            final isSelected = selectedAnswer == oi;
            final isCorrectOption = oi == question.correct;

            Color borderColor = Theme.of(context).dividerColor;
            Color bgColor = Colors.transparent;
            Color textColor = Theme.of(context).colorScheme.onSurface;

            if (answered) {
              if (isCorrectOption) {
                borderColor = AppColors.teachColor;
                bgColor = AppColors.teachColor.withValues(alpha: 0.08);
                textColor = AppColors.teachColor;
              } else if (isSelected && !isCorrectOption) {
                borderColor = Colors.red;
                bgColor = Colors.red.withValues(alpha: 0.06);
                textColor = Colors.red;
              }
            } else if (isSelected) {
              borderColor = AppColors.primary;
              bgColor = AppColors.primary.withValues(alpha: 0.06);
            }

            return GestureDetector(
              onTap: answered ? null : () => onAnswer(oi),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Text(
                      String.fromCharCode(65 + oi),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(fontSize: 13, color: textColor),
                      ),
                    ),
                    if (answered && isCorrectOption)
                      const Icon(Icons.check_circle, size: 18, color: AppColors.teachColor),
                    if (answered && isSelected && !isCorrectOption)
                      const Icon(Icons.cancel, size: 18, color: Colors.red),
                  ],
                ),
              ),
            );
          }),
          if (answered) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isCorrect == true ? AppColors.teachColor : Colors.red).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                question.explanation,
                style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
