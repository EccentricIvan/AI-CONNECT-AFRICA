import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_definitions.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../learn/path/path_provider.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: studentAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (student) {
            if (student == null) {
              return const Center(child: Text('No student profile found.'));
            }
            return _AchievementsBody(student: student);
          },
        ),
      ),
    );
  }
}

// ── Badge progress ────────────────────────────────────────────────────────────

enum _BadgeState { earned, inProgress, open, locked }

/// Where a learner stands on one badge. [target] is null for badges whose
/// trigger is counted per session and never stored, so there is nothing to
/// show progress against — those advertise their points instead.
class _BadgeProgress {
  const _BadgeProgress(this.def, {required this.earned, this.current = 0, this.target});

  final BadgeDef def;
  final bool earned;
  final int current;
  final int? target;

  _BadgeState get state {
    if (earned) return _BadgeState.earned;
    final t = target;
    if (t == null) return _BadgeState.open;
    return current > 0 ? _BadgeState.inProgress : _BadgeState.locked;
  }
}

/// Progress towards each badge, from the same stored counts
/// [BadgeService] awards on.
List<_BadgeProgress> _progressFor({
  required Set<String> earnedIds,
  required Student student,
  required List<LearningPath> paths,
  required int projectCount,
}) {
  // LearningPaths (auto-generated) plus the curriculum browser's own
  // lessons — two separate tracks that both count as "a lesson done".
  var lessonsDone =
      paths.fold(0, (s, p) => s + p.completedLessons) +
          student.totalLessonsCompleted;
  // A student can hold the First Step badge with both trackers reading 0 —
  // e.g. a regenerated path resets LearningPaths.completedLessons
  // (path_dao.dart uses insertOnConflictUpdate) without touching the badge
  // already recorded. Completed sitting next to "0 lessons done" is exactly
  // the contradiction that made the whole screen read as hardcoded.
  if (earnedIds.contains('first_lesson') && lessonsDone < 1) lessonsDone = 1;
  LearningPath? bestPath;
  for (final p in paths) {
    if (p.totalLessons <= 0) continue;
    if (bestPath == null ||
        p.completedLessons / p.totalLessons >
            bestPath.completedLessons / bestPath.totalLessons) {
      bestPath = p;
    }
  }

  (int, int?) counts(String id) => switch (id) {
        'first_lesson' => (lessonsDone, 1),
        'path_master' =>
          (bestPath?.completedLessons ?? 0, bestPath?.totalLessons ?? 12),
        'polymath' => (paths.length, 3),
        'practice_starter' => (student.totalPracticeAttempted, 1),
        'sharp_mind' => (student.totalPracticeCorrect, 5),
        'scenario_solver' => (student.totalScenariosCompleted, 5),
        'creator' => (projectCount, 1),
        'consistent_learner' => (student.streakDays, 7),
        'century' => (student.totalPoints, 100),
        _ => (0, null),
      };

  return [
    for (final def in allBadges)
      () {
        final (current, target) = counts(def.id);
        return _BadgeProgress(
          def,
          earned: earnedIds.contains(def.id),
          current: target == null ? 0 : current.clamp(0, target),
          target: target,
        );
      }(),
  ];
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _AchievementsBody extends ConsumerStatefulWidget {
  const _AchievementsBody({required this.student});
  final Student student;

  @override
  ConsumerState<_AchievementsBody> createState() => _AchievementsBodyState();
}

class _AchievementsBodyState extends ConsumerState<_AchievementsBody> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final badgesAsync = ref.watch(earnedBadgesProvider(student.id));
    // BadgeService keeps this fresh on every Practice/Apply/streak/award
    // event without touching activeStudentProvider (which the chat, router
    // and app shell all watch) — see studentStatsProvider's doc comment.
    // Falls back to the (possibly one-tick-stale) student passed in while
    // the first fetch is in flight.
    final liveStudent =
        ref.watch(studentStatsProvider(student.id)).valueOrNull ?? student;
    // Progress is a nicety — until these load, badges simply read as locked.
    final paths = ref.watch(studentPathsProvider).valueOrNull ?? const [];
    // A "project" is anything saved from Create mode — the guided project
    // builder, the App Builder, or the Website Builder — so the Creator
    // badge and the count it shows reflect all three, not just one.
    final createProjects =
        ref.watch(studentProjectsProvider(student.id)).valueOrNull ?? const [];
    final appProjects =
        ref.watch(studentAppBuilderProjectsProvider(student.id)).valueOrNull ??
            const [];
    final websites =
        ref.watch(studentWebsitesProvider(student.id)).valueOrNull ?? const [];
    final projectCount =
        createProjects.length + appProjects.length + websites.length;

    return badgesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (earned) {
        final earnedIds = earned.map((b) => b.badgeId).toSet();
        final progress = _progressFor(
          earnedIds: earnedIds,
          student: liveStudent,
          paths: paths,
          projectCount: projectCount,
        );
        final earnedCount = progress.where((p) => p.earned).length;
        // Earned first, then the ones under way — the preview row leads with
        // what the learner has done and what is closest.
        final ordered = [...progress]
          ..sort((a, b) => a.state.index.compareTo(b.state.index));

        return MaxWidth(
          maxWidth: 1200,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 760;
            final hPad = wide ? 32.0 : 16.0;
            final cols = adaptiveColumns(box.maxWidth - hPad * 2,
                min: 2, max: 4, itemWidth: 230);
            final shown =
                _showAll ? ordered : ordered.take(cols).toList();

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, wide ? 28 : 16, hPad, 0),
                  sliver: SliverList.list(children: [
                    _Hero(wide: wide),
                    SizedBox(height: wide ? 28 : 20),
                    _SummaryCard(
                      student: student,
                      earned: earnedCount,
                      total: allBadges.length,
                      // The one-row layout needs room for the ring and both
                      // stat tiles side by side; below that it stacks.
                      wide: box.maxWidth >= 1000,
                    ),
                    SizedBox(height: wide ? 32 : 24),
                    _AreaProgress(
                      student: liveStudent,
                      paths: paths,
                      createCount: createProjects.length,
                      appCount: appProjects.length,
                      websiteCount: websites.length,
                      cols: adaptiveColumns(box.maxWidth - hPad * 2,
                          min: 2, max: 4, itemWidth: 210),
                      firstLessonEarned: earnedIds.contains('first_lesson'),
                    ),
                    SizedBox(height: wide ? 32 : 24),
                    _BadgesHeader(
                      showAll: _showAll,
                      canExpand: ordered.length > cols,
                      onToggle: () => setState(() => _showAll = !_showAll),
                    ),
                    const SizedBox(height: 14),
                  ]),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _BadgeCard(progress: shown[i]),
                      childCount: shown.length,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: 236,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 32),
                  sliver: const SliverToBoxAdapter(child: _CertificatesLink()),
                ),
              ],
            );
          }),
        );
      },
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'Achievements').toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 3.2,
            color: ac.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'Keep learning, keep growing.'),
          style: TextStyle(
            fontFamily: 'Saira',
            fontSize: wide ? 40 : 28,
            fontWeight: FontWeight.w700,
            height: 1.1,
            letterSpacing: -0.6,
            color: ac.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'Track your progress and celebrate your milestones.'),
          style: TextStyle(fontSize: wide ? 16 : 14, color: ac.textSecondary),
        ),
      ],
    );

    if (!wide) return heading;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 24),
        Container(width: 48, height: 1.5, color: ac.textSecondary),
        const SizedBox(width: 20),
        Text(
          '${tr(context, 'Knowledge today.')}\n'
          '${tr(context, 'Greater opportunities tomorrow.')}',
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: ac.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.student,
    required this.earned,
    required this.total,
    required this.wide,
  });

  final Student student;
  final int earned;
  final int total;
  final bool wide;

  String _encouragement(BuildContext context, double ratio) {
    if (ratio >= 1) return tr(context, 'Every badge earned — amazing work!');
    if (ratio >= 0.6) return tr(context, 'Almost there — keep going!');
    if (ratio > 0) return tr(context, "You're making great progress!");
    return tr(context, 'Every badge starts with one step.');
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final ratio = total > 0 ? earned / total : 0.0;

    final ring = _ProgressRing(ratio: ratio, size: wide ? 168 : 132);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          student.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Saira',
            fontSize: wide ? 24 : 20,
            fontWeight: FontWeight.w700,
            color: ac.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          trFill(context, '{earned} of {total} badges earned',
              {'earned': '$earned', 'total': '$total'}),
          style: TextStyle(fontSize: 15, color: ac.textSecondary),
        ),
        const SizedBox(height: 18),
        _Bar(value: ratio, height: 10),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.trending_up_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _encouragement(context, ratio),
                style: TextStyle(fontSize: 13, color: ac.textPrimary),
              ),
            ),
          ],
        ),
      ],
    );

    final points = _StatTile(
      icon: Icons.star_rounded,
      color: AppColors.primary,
      value: '${student.totalPoints}',
      label: tr(context, 'Total points'),
    );
    final streak = _StatTile(
      icon: Icons.local_fire_department_rounded,
      color: AppColors.accentOrange,
      value: '${student.streakDays}',
      label: tr(context, 'Day streak'),
    );

    Widget divider() => Container(
          width: 1,
          height: 110,
          margin: const EdgeInsets.symmetric(horizontal: 28),
          color: ac.border,
        );

    return Container(
      padding: EdgeInsets.all(wide ? 28 : 20),
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ac.border),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: wide
          ? Row(
              children: [
                ring,
                divider(),
                Expanded(flex: 5, child: info),
                divider(),
                Expanded(flex: 2, child: points),
                divider(),
                Expanded(flex: 2, child: streak),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ring,
                    const SizedBox(width: 20),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(height: 1, color: ac.border),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: points),
                    const SizedBox(width: 12),
                    Expanded(child: streak),
                  ],
                ),
              ],
            ),
    );
  }
}

// ── Progress by area ─────────────────────────────────────────────────────────
//
// The badge grid alone hides most of a learner's activity — Practice, Apply
// and Create only show up there once a badge is close, and the grid itself
// is often collapsed to a couple of cards. This section is what actually
// grounds "not hardcoded": every value is read live from the same tables the
// badges use (LearningPaths, the practice/scenario counters on Students, and
// the three project tables), one card per connected feature.
class _AreaProgress extends StatelessWidget {
  const _AreaProgress({
    required this.student,
    required this.paths,
    required this.createCount,
    required this.appCount,
    required this.websiteCount,
    required this.cols,
    required this.firstLessonEarned,
  });

  final Student student;
  final List<LearningPath> paths;
  final int createCount;
  final int appCount;
  final int websiteCount;
  final int cols;
  final bool firstLessonEarned;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    var lessonsDone =
        paths.fold(0, (s, p) => s + p.completedLessons) +
            student.totalLessonsCompleted;
    // See the matching floor in _progressFor.
    if (firstLessonEarned && lessonsDone < 1) lessonsDone = 1;
    LearningPath? bestPath;
    for (final p in paths) {
      if (p.totalLessons <= 0) continue;
      if (bestPath == null ||
          p.completedLessons / p.totalLessons >
              bestPath.completedLessons / bestPath.totalLessons) {
        bestPath = p;
      }
    }
    final attempted = student.totalPracticeAttempted;
    final correct = student.totalPracticeCorrect;
    final accuracy = attempted > 0 ? (correct / attempted * 100).round() : 0;
    final totalProjects = createCount + appCount + websiteCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            tr(context, 'Progress by area'),
            style: TextStyle(
              fontFamily: 'Saira',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
        ),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 132,
          ),
          children: [
            _AreaCard(
              icon: Icons.school_rounded,
              color: AppColors.learnColor,
              title: tr(context, 'Learn'),
              value: trFill(
                  context,
                  lessonsDone == 1 ? '{n} lesson done' : '{n} lessons done',
                  {'n': '$lessonsDone'}),
              detail: bestPath == null
                  ? tr(context, 'Start a learning path')
                  : trFill(context, '{title}: {done}/{total}', {
                      'title': bestPath.topic,
                      'done': '${bestPath.completedLessons}',
                      'total': '${bestPath.totalLessons}',
                    }),
              ratio: bestPath == null || bestPath.totalLessons <= 0
                  ? 0
                  : bestPath.completedLessons / bestPath.totalLessons,
              onTap: () => GoRouter.of(context).push('/learn'),
            ),
            _AreaCard(
              icon: Icons.quiz_rounded,
              color: AppColors.practiceColor,
              title: tr(context, 'Practice'),
              value: trFill(context, '{correct}/{attempted} correct',
                  {'correct': '$correct', 'attempted': '$attempted'}),
              detail: attempted == 0
                  ? tr(context, 'Answer your first question')
                  : trFill(
                      context, '{pct}% accuracy', {'pct': '$accuracy'}),
              ratio: correct / 5,
              onTap: () => GoRouter.of(context).push('/practice'),
            ),
            _AreaCard(
              icon: Icons.explore_rounded,
              color: AppColors.createColor,
              title: tr(context, 'Apply'),
              value: trFill(
                  context,
                  student.totalScenariosCompleted == 1
                      ? '{n} scenario completed'
                      : '{n} scenarios completed',
                  {'n': '${student.totalScenariosCompleted}'}),
              detail: tr(context, 'Real-world problem solving'),
              ratio: student.totalScenariosCompleted / 5,
              onTap: () => GoRouter.of(context).push('/practice'),
            ),
            _AreaCard(
              icon: Icons.lightbulb_rounded,
              color: AppColors.teachColor,
              title: tr(context, 'Create'),
              value: trFill(
                  context,
                  totalProjects == 1
                      ? '{n} project saved'
                      : '{n} projects saved',
                  {'n': '$totalProjects'}),
              detail: tr(context, 'Guided, App & Website builders'),
              ratio: totalProjects.clamp(0, 1).toDouble(),
              onTap: () => GoRouter.of(context).push('/projects'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.detail,
    required this.ratio,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String detail;
  final double ratio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return StudioCard(
      accent: color,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StudioIconChip(icon: icon, color: color, size: 34, radius: 11),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: ac.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: ac.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _Bar(value: ratio, height: 6),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: ac.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.ratio, required this.size});
  final double ratio;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final pct = (ratio * 100).round();

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: size * 0.075,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '$pct',
                    style: TextStyle(
                      fontFamily: 'Saira',
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text: '%',
                    style: TextStyle(
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]),
                style: TextStyle(color: ac.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                // Distinct from the per-badge "Completed" pill below — this
                // ring specifically is badges earned ÷ total badges, not a
                // syllabus/lesson completion percentage. 'Badges' is already
                // translated across every supported language, unlike a new
                // English-only label would be.
                tr(context, 'Badges'),
                style: TextStyle(
                  fontSize: size * 0.085,
                  color: ac.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: ac.isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Saira',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: ac.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: ac.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, this.height = 8});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

class _BadgesHeader extends StatelessWidget {
  const _BadgesHeader({
    required this.showAll,
    required this.canExpand,
    required this.onToggle,
  });

  final bool showAll;
  final bool canExpand;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            tr(context, 'Your Badges'),
            style: TextStyle(
              fontFamily: 'Saira',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
        ),
        if (canExpand)
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(context, showAll ? 'Show less' : 'View all'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Icon(
                  showAll
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.arrow_forward_rounded,
                  size: 18,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.progress});
  final _BadgeProgress progress;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final def = progress.def;
    final state = progress.state;
    final muted = state == _BadgeState.locked;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ac.border),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (muted ? AppColors.accentSlate : AppColors.primary)
                  .withValues(alpha: ac.isDark ? 0.18 : 0.08),
            ),
            child: Icon(
              def.icon,
              size: 30,
              color: muted ? AppColors.accentSlate : AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tr(context, def.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              tr(context, def.description),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ac.textSecondary,
              ),
            ),
          ),
          _footer(context, ac),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppColors ac) {
    final def = progress.def;
    switch (progress.state) {
      case _BadgeState.earned:
        return _Pill(
          color: AppColors.accentGreen,
          icon: Icons.check_rounded,
          label: tr(context, 'Completed'),
        );
      case _BadgeState.inProgress:
        return Column(
          children: [
            _Bar(value: progress.current / progress.target!),
            const SizedBox(height: 10),
            Text(
              '${progress.current} / ${progress.target}',
              style: TextStyle(fontSize: 13, color: ac.textSecondary),
            ),
          ],
        );
      case _BadgeState.open:
        return _Pill(
          color: AppColors.primary,
          label: trFill(context, '+{points} pts', {'points': '${def.points}'}),
        );
      case _BadgeState.locked:
        return _Pill(
          color: AppColors.accentSlate,
          icon: Icons.lock_rounded,
          label: tr(context, 'Locked'),
        );
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label, this.icon});
  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: ac.isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Certificates no longer has its own sidebar entry — it lives here, under the
/// badges, and opens as a pushed screen with a back button.
class _CertificatesLink extends StatelessWidget {
  const _CertificatesLink();

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return StudioCard(
      accent: AppColors.accentViolet,
      onTap: () => GoRouter.of(context).push('/certificates'),
      child: Row(
        children: [
          const StudioIconChip(
            icon: Icons.workspace_premium_rounded,
            color: AppColors.accentViolet,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'Certificates'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ac.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(context, 'Celebrate completed paths'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ac.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: ac.textHint),
        ],
      ),
    );
  }
}
