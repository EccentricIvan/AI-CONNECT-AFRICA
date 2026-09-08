import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_models.dart';
import '../../curriculum/curriculum_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/quiz_ai_answer.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import 'practice_providers.dart';
import 'quiz_generator.dart';
import 'scenario_models.dart';

// ── Topic list ────────────────────────────────────────────────────────────────

const _topics = [
  'Mathematics',
  'Physics',
  'Biology',
  'Chemistry',
  'Programming',
  'Web Development',
  'App Development',
  'AI & Data',
  'Entrepreneurship',
  'Agriculture',
  'History',
  'Geography',
  'English Writing',
  'Economics',
  'Arts',
  'Project Ignite AI',
];

// ── Root screen ───────────────────────────────────────────────────────────────

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
appBar: StudioAppBar(
          title: tr(context, 'Practice'),
          subtitle: tr(context, 'Sharpen your skills'),
          icon: Icons.fact_check_rounded,
          iconColor: const Color(0xFF2EBB6E),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.quiz_outlined), text: tr(context, 'Practice')),
              Tab(icon: const Icon(Icons.explore_outlined), text: tr(context, 'Apply')),
            ],
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        body: const MaxWidth(
          child: TabBarView(children: [_PracticeTab(), _ApplyTab()]),
        ),
      ),
    );
  }
}

// ── Shared topic picker ───────────────────────────────────────────────────────

class _TopicPicker extends ConsumerWidget {
  const _TopicPicker({
    required this.selected,
    required this.onSelect,
    required this.color,
  });

  final String selected;
  final void Function(String) onSelect;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Merge student interests with fixed topic list
    final studentAsync = ref.watch(activeStudentProvider);
    final studentInterests =
        studentAsync.valueOrNull?.interestsJson
            .replaceAll('[', '')
            .replaceAll(']', '')
            .replaceAll('"', '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    final allTopics = [
      ...studentInterests.where((i) => !_topics.contains(i)),
      ..._topics,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: DropdownButtonFormField<String>(
        initialValue: selected.isEmpty ? null : selected,
        decoration: InputDecoration(
          labelText: 'Choose a topic',
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: color, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        dropdownColor: Theme.of(context).colorScheme.surface,
        isExpanded: true,
        hint: Text('Select a topic', style: TextStyle(color: Theme.of(context).hintColor)),
        items: allTopics
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) {
          if (v != null) onSelect(v);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PRACTICE TAB — Multiple choice exercises
// ══════════════════════════════════════════════════════════════════════════════

class _PracticeTab extends ConsumerStatefulWidget {
  const _PracticeTab();

  @override
  ConsumerState<_PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends ConsumerState<_PracticeTab> {
  String _selectedTopic = '';
  List<QuizQuestion> _questions = [];
  int _currentQ = 0;
  int? _selectedAnswer;
  int _score = 0;
  int _total = 0;
  bool _answered = false;

  void _loadQuestions(String topic) async {
    final curriculum = ref.read(curriculumServiceProvider);
    await curriculum.loadAll();

    final subjectId = _topicToSubjectId(topic);
    final subject = await curriculum.load(subjectId);
    if (subject == null) return;

    final allQuiz = <QuizQuestion>[];
    for (final unit in subject.units) {
      for (final lesson in unit.lessons) {
        allQuiz.addAll(lesson.quiz);
      }
    }
    allQuiz.shuffle();

    setState(() {
      _selectedTopic = topic;
      _questions = allQuiz.take(10).toList();
      _currentQ = 0;
      _selectedAnswer = null;
      _answered = false;
      _score = 0;
      _total = 0;
    });

    _appendAdaptiveQuestions(topic);
  }

  /// Adds a few AI-generated questions calibrated to the student's current
  /// mastery level, on top of the static curriculum bank. Best-effort: if
  /// generation is slow, fails, or the topic changes, this just quietly
  /// contributes nothing — the static quiz already works on its own.
  Future<void> _appendAdaptiveQuestions(String topic) async {
    try {
      final student = await ref.read(activeStudentProvider.future);
      if (student == null) return;
      final db = ref.read(dbProvider);
      final progress = await db.sessionDao.getTopicProgress(student.id);
      final mastery =
          progress.where((p) => p.topic == topic).fold(0, (_, p) => p.level);

      final engine = await ref.read(engineLoadedProvider.future);
      final generator = QuizGenerator(engine: engine);
      for (var i = 0; i < 3; i++) {
        final q = await generator.generate(topic: topic, masteryLevel: mastery);
        if (!mounted || _selectedTopic != topic) return;
        if (q != null) setState(() => _questions = [..._questions, q]);
      }
    } catch (_) {
      // Adaptive bonus questions are optional.
    }
  }

  String _topicToSubjectId(String topic) {
    final map = {
      'Mathematics': 'mathematics', 'Physics': 'physics', 'Biology': 'biology',
      'Chemistry': 'chemistry', 'Programming': 'programming',
      'Web Development': 'web_development', 'App Development': 'app_development',
      'AI & Data': 'ai_and_data', 'Entrepreneurship': 'entrepreneurship',
      'Agriculture': 'agriculture', 'History': 'history', 'Geography': 'geography',
      'English Writing': 'english_writing', 'Economics': 'economics', 'Arts': 'arts', 'Project Ignite AI': 'ignite_ai',
    };
    return map[topic] ?? topic.toLowerCase().replaceAll(' ', '_');
  }

  Future<void> _answer(int index) async {
    if (_answered) return;
    setState(() {
      _selectedAnswer = index;
      _answered = true;
      _total++;
      if (index == _questions[_currentQ].correct) _score++;
    });

    final student = await ref.read(activeStudentProvider.future);
    if (student != null) {
      await ref.read(badgeServiceProvider).onPracticeAnswered(student.id, _score);
    }
  }

  void _next() {
    if (_currentQ < _questions.length - 1) {
      setState(() {
        _currentQ++;
        _selectedAnswer = null;
        _answered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTopic.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _TopicPicker(
              selected: _selectedTopic,
              color: AppColors.primary,
              onSelect: _loadQuestions,
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
    }

    if (_questions.isEmpty) {
      return Center(child: Text('No questions found for $_selectedTopic'));
    }

    // Done
    if (_currentQ >= _questions.length - 1 && _answered) {
      final allDone = _total == _questions.length;
      if (allDone) {
        return _QuizResult(
          score: _score,
          total: _questions.length,
          onRestart: () => _loadQuestions(_selectedTopic),
          onChangeTopic: () => setState(() { _selectedTopic = ''; _questions = []; }),
        );
      }
    }

    final q = _questions[_currentQ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(_selectedTopic, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
              const Spacer(),
              Text('${_currentQ + 1}/${_questions.length}', style: TextStyle(color: Theme.of(context).hintColor)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (_currentQ + 1) / _questions.length,
            backgroundColor: Theme.of(context).dividerColor,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text('Score: $_score/$_total', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
          const SizedBox(height: 20),

          // Question
          Text(q.question, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: Theme.of(context).colorScheme.onSurface)),
          QuizAiAnswer(key: ValueKey('practice-$_currentQ-${q.question}'), question: q),
          const SizedBox(height: 16),

          // Options
          ...q.options.asMap().entries.map((e) {
            final oi = e.key;
            final option = e.value;
            final isSelected = _selectedAnswer == oi;
            final isCorrect = oi == q.correct;

            Color borderColor = Theme.of(context).dividerColor;
            Color bgColor = Colors.transparent;

            if (_answered) {
              if (isCorrect) {
                borderColor = AppColors.teachColor;
                bgColor = AppColors.teachColor.withValues(alpha: 0.08);
              } else if (isSelected) {
                borderColor = Colors.red;
                bgColor = Colors.red.withValues(alpha: 0.06);
              }
            } else if (isSelected) {
              borderColor = AppColors.primary;
              bgColor = AppColors.primary.withValues(alpha: 0.06);
            }

            return GestureDetector(
              onTap: () => _answer(oi),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Text(String.fromCharCode(65 + oi), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(option, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface))),
                    if (_answered && isCorrect) const Icon(Icons.check_circle, size: 18, color: AppColors.teachColor),
                    if (_answered && isSelected && !isCorrect) const Icon(Icons.cancel, size: 18, color: Colors.red),
                  ],
                ),
              ),
            );
          }),

          // Explanation
          if (_answered) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_selectedAnswer == q.correct ? AppColors.teachColor : Colors.red).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(q.explanation, style: TextStyle(fontSize: 13, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.arrow_forward),
                label: Text(_currentQ < _questions.length - 1 ? 'Next Question' : 'See Results'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizResult extends StatelessWidget {
  const _QuizResult({required this.score, required this.total, required this.onRestart, required this.onChangeTopic});
  final int score, total;
  final VoidCallback onRestart, onChangeTopic;

  @override
  Widget build(BuildContext context) {
    final percent = (score / total * 100).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$score/$total', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.teachColor)),
            Text('$percent%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.teachColor)),
            const SizedBox(height: 8),
            Text(
              percent >= 80 ? 'Excellent!' : percent >= 60 ? 'Good job!' : 'Keep practicing!',
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onRestart, icon: const Icon(Icons.refresh), label: const Text('Try Again'), style: FilledButton.styleFrom(backgroundColor: AppColors.primary)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onChangeTopic, icon: const Icon(Icons.swap_horiz), label: const Text('Change Subject')),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// APPLY TAB — Real-world scenarios
// ══════════════════════════════════════════════════════════════════════════════

class _ApplyTab extends ConsumerStatefulWidget {
  const _ApplyTab();

  @override
  ConsumerState<_ApplyTab> createState() => _ApplyTabState();
}

class _ApplyTabState extends ConsumerState<_ApplyTab> {
  final _responseController = TextEditingController();

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(applyProvider);

    // Sync text controller when state resets
    ref.listen(applyProvider, (prev, next) {
      if (next.response.isEmpty && _responseController.text.isNotEmpty) {
        _responseController.clear();
      }
    });

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopicPicker(
            selected: state.topic,
            color: AppColors.primary,
            onSelect: (t) {
              ref.read(applyProvider.notifier).setTopic(t);
            },
          ),
          const SizedBox(height: 16),

          if (state.topic.isNotEmpty &&
              state.scenario == null &&
              !state.isGeneratingScenario)
            _StartCard(
              topic: state.topic,
              color: AppColors.primary,
              icon: Icons.explore,
              label: 'Give me a scenario',
              onTap: () => ref.read(applyProvider.notifier).generateScenario(),
            ),

          if (state.isGeneratingScenario)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),

          if (state.error != null)
            _ErrorCard(
              message: state.error!,
              onRetry: () =>
                  ref.read(applyProvider.notifier).generateScenario(),
            ),

          if (state.scenario != null)
            _ScenarioCard(
              scenario: state.scenario!,
              state: state,
              responseController: _responseController,
              onResponseChanged: (t) =>
                  ref.read(applyProvider.notifier).setResponse(t),
              onSubmit: () => ref.read(applyProvider.notifier).evaluate(),
              onNext: () => ref.read(applyProvider.notifier).nextScenario(),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.state,
    required this.responseController,
    required this.onResponseChanged,
    required this.onSubmit,
    required this.onNext,
  });

  final Scenario scenario;
  final ApplyState state;
  final TextEditingController responseController;
  final void Function(String) onResponseChanged;
  final VoidCallback onSubmit;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Situation card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.place,
                      size: 15,
                      color: AppColors.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'SCENARIO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  scenario.situation,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Challenge question
          Text(
            scenario.challenge,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // Response input
          if (state.feedback == null) ...[
            TextField(
              controller: responseController,
              onChanged: onResponseChanged,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: 'Describe what you would do and why…',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: state.isEvaluating
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: state.response.trim().isEmpty
                          ? null
                          : onSubmit,
                      icon: const Icon(Icons.send),
                      label: const Text('Submit my response'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
            ),
          ],

          // Feedback
          if (state.feedback != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.lightbulb,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'AI Feedback',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    state.feedback!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.refresh),
                label: const Text('New scenario'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared utility widgets ────────────────────────────────────────────────────

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.topic,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String topic;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 14),
            Text(
              topic,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
