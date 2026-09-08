import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class _TeachState {
  const _TeachState({
    this.topic = '',
    this.explanation = '',
    this.score,
    this.strengths = '',
    this.improve = '',
    this.overall = '',
    this.isEvaluating = false,
    this.newBadge = '',
  });

  final String topic;
  final String explanation;
  final int? score;
  final String strengths;
  final String improve;
  final String overall;
  final bool isEvaluating;
  final String newBadge;

  bool get hasResult => score != null;

  _TeachState copyWith({
    String? topic,
    String? explanation,
    int? score,
    String? strengths,
    String? improve,
    String? overall,
    bool? isEvaluating,
    String? newBadge,
    bool clearScore = false,
  }) => _TeachState(
    topic: topic ?? this.topic,
    explanation: explanation ?? this.explanation,
    score: clearScore ? null : score ?? this.score,
    strengths: strengths ?? this.strengths,
    improve: improve ?? this.improve,
    overall: overall ?? this.overall,
    isEvaluating: isEvaluating ?? this.isEvaluating,
    newBadge: newBadge ?? this.newBadge,
  );
}

class _TeachNotifier extends AutoDisposeNotifier<_TeachState> {
  @override
  _TeachState build() => const _TeachState();

  void setTopic(String t) =>
      state = state.copyWith(topic: t, clearScore: true, explanation: '');
  void setExplanation(String t) => state = state.copyWith(explanation: t);

  Future<void> evaluate() async {
    if (state.topic.isEmpty || state.explanation.trim().isEmpty) return;
    state = state.copyWith(isEvaluating: true, clearScore: true);

    try {
      final engine = await ref.read(engineLoadedProvider.future);
      final englishExplanation = await localizeOutgoing(ref, state.explanation);
      final prompt =
          '''A student explained "${state.topic}" as follows:
"$englishExplanation"

Score this explanation out of 100. Your response MUST follow this exact format:
SCORE: [number 0-100]
STRENGTHS: [one sentence about what they got right]
IMPROVE: [one sentence about what to strengthen]
OVERALL: [one encouraging sentence]

Rate the explanation now:''';

      final raw = await engine.generate(
        prompt: prompt,
        maxTokens: 200,
        temperature: 0.4,
      );

      final parsed = _parse(raw);
      final score = parsed['score'] ?? 50;

      // Badge check
      String badge = '';
      final student = await ref.read(activeStudentProvider.future);
      if (student != null) {
        final badges = await ref
            .read(badgeServiceProvider)
            .onTeachScored(student.id, score);
        if (badges.isNotEmpty) badge = badges.first.name;
      }

      final blob = await localizeIncoming(
        ref,
        '${parsed['strengths'] ?? 'Good attempt!'}\n---\n'
        '${parsed['improve'] ?? 'Keep practising.'}\n---\n'
        '${parsed['overall'] ?? 'Great effort!'}',
      );
      final parts = blob.split(RegExp(r'\n---\n'));
      state = state.copyWith(
        score: score,
        strengths: parts.isNotEmpty ? parts[0].trim() : 'Good attempt!',
        improve: parts.length > 1 ? parts[1].trim() : 'Keep practising.',
        overall: parts.length > 2 ? parts[2].trim() : 'Great effort!',
        isEvaluating: false,
        newBadge: badge,
      );
    } catch (_) {
      state = state.copyWith(isEvaluating: false);
    }
  }

  Map<String, dynamic> _parse(String raw) {
    final result = <String, dynamic>{};
    final scoreMatch = RegExp(r'SCORE:\s*(\d+)').firstMatch(raw);
    if (scoreMatch != null) {
      result['score'] = int.tryParse(scoreMatch.group(1) ?? '50') ?? 50;
    }
    final strengthsMatch = RegExp(
      r'STRENGTHS:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (strengthsMatch != null) {
      result['strengths'] = strengthsMatch.group(1)?.trim();
    }
    final improveMatch = RegExp(
      r'IMPROVE:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (improveMatch != null) {
      result['improve'] = improveMatch.group(1)?.trim();
    }
    final overallMatch = RegExp(
      r'OVERALL:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (overallMatch != null) {
      result['overall'] = overallMatch.group(1)?.trim();
    }
    return result;
  }

  void reset() => state = _TeachState(topic: state.topic);
}

final _teachProvider = AutoDisposeNotifierProvider<_TeachNotifier, _TeachState>(
  _TeachNotifier.new,
);

// ── Screen ────────────────────────────────────────────────────────────────────

class TeachScreen extends ConsumerStatefulWidget {
  const TeachScreen({super.key});

  @override
  ConsumerState<TeachScreen> createState() => _TeachScreenState();
}

class _TeachScreenState extends ConsumerState<TeachScreen> {
  final _explController = TextEditingController();

  @override
  void dispose() {
    _explController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_teachProvider);

    ref.listen(_teachProvider, (prev, next) {
      if (next.explanation.isEmpty && _explController.text.isNotEmpty) {
        _explController.clear();
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Teach'),
        subtitle: tr(context, 'Explain it to master it'),
        icon: Icons.school_rounded,
        iconColor: const Color(0xFF2EB8A0),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: MaxWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.teachColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.teachColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.school, color: AppColors.teachColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Explain a topic clearly. The better your explanation, the higher your score!',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Topic picker
              const Text(
                'Choose a topic',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _TopicChips(
                selected: state.topic,
                onSelect: (t) {
                  ref.read(_teachProvider.notifier).setTopic(t);
                  _explController.clear();
                },
              ),
              const SizedBox(height: 28),

              if (state.topic.isNotEmpty && !state.hasResult) ...[
                Text(
                  'Explain "${state.topic}" in your own words',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Write as if you are teaching a friend. Use examples.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _explController,
                  onChanged: ref.read(_teachProvider.notifier).setExplanation,
                  maxLines: 8,
                  minLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Type your explanation here…',
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
                        color: AppColors.teachColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                          onPressed: state.explanation.trim().isEmpty
                              ? null
                              : () => ref
                                    .read(_teachProvider.notifier)
                                    .evaluate(),
                          icon: const Icon(Icons.send),
                          label: const Text('Submit for scoring'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                ),
              ],

              // Result
              if (state.hasResult) ...[
                _ScoreCard(state: state),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(_teachProvider.notifier).reset(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          ref.read(_teachProvider.notifier).setTopic('');
                          _explController.clear();
                        },
                        icon: const Icon(Icons.topic),
                        label: const Text('New topic'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Score card ────────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.state});
  final _TeachState state;

  Color get _scoreColor {
    if (state.score! >= 80) return AppColors.teachColor;
    if (state.score! >= 50) return AppColors.createColor;
    return AppColors.practiceColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (state.newBadge.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.teachColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.teachColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Badge Earned!',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.teachColor,
                      ),
                    ),
                    Text(
                      state.newBadge,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _scoreColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                '${state.score}/100',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: _scoreColor,
                ),
              ),
              Text(
                _label(state.score!),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _scoreColor,
                ),
              ),
              const SizedBox(height: 24),
              _FeedbackRow(
                icon: Icons.check_circle_outline,
                color: AppColors.teachColor,
                label: 'Strengths',
                text: state.strengths,
              ),
              const SizedBox(height: 12),
              _FeedbackRow(
                icon: Icons.arrow_upward,
                color: AppColors.practiceColor,
                label: 'Improve',
                text: state.improve,
              ),
              const SizedBox(height: 12),
              _FeedbackRow(
                icon: Icons.auto_awesome,
                color: AppColors.createColor,
                label: 'Overall',
                text: state.overall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _label(int s) {
    if (s >= 90) return 'Excellent!';
    if (s >= 80) return 'Great job!';
    if (s >= 60) return 'Good effort';
    if (s >= 40) return 'Keep practising';
    return 'Keep going!';
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Topic chips ───────────────────────────────────────────────────────────────

const _teachTopics = [
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
];

class _TopicChips extends StatelessWidget {
  const _TopicChips({required this.selected, required this.onSelect});
  final String selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _teachTopics.map((t) {
        final sel = selected == t;
        return ChoiceChip(
          label: Text(t),
          selected: sel,
          onSelected: (_) => onSelect(t),
          selectedColor: AppColors.primary.withValues(alpha: 0.12),
          side: BorderSide(
            color: sel ? AppColors.primary : Theme.of(context).dividerColor,
          ),
          labelStyle: TextStyle(
            color: sel ? AppColors.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
          ),
          checkmarkColor: AppColors.primary,
        );
      }).toList(),
    );
  }
}
