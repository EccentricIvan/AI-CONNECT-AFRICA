import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../features/learn/path/path_models.dart';
import '../../features/learn/path/path_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

final _desktopNameProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('student_name') ?? 'Learner';
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String name;
    Student? student;
    if (kIsWeb) {
      name = ref.watch(_desktopNameProvider).valueOrNull ?? 'Learner';
    } else {
      final studentAsync = ref.watch(activeStudentProvider);
      student = studentAsync.valueOrNull;
      name = student?.name ?? 'Learner';
    }

    final paths = ref.watch(studentPathsProvider).valueOrNull ?? const [];
    final parsedPaths = paths.map(parsedFromRow).toList();
    final continuePath = _pickContinuePath(parsedPaths);
    final lessonsCompleted = parsedPaths.fold<int>(
      0,
      (sum, p) => sum + p.completedLessons,
    );
    final lessonsTotal = parsedPaths.fold<int>(
      0,
      (sum, p) => sum + p.totalLessons,
    );
    final overallProgress = lessonsTotal == 0
        ? 0.0
        : lessonsCompleted / lessonsTotal;
    // Nothing here is date-filtered — these are the active path's lifetime
    // counts, so the strip reports the path's real progress rather than a
    // "today" figure it cannot compute.
    final activeDone = continuePath?.completedLessons ?? 0;
    final activeTotal = continuePath?.totalLessons ?? 0;
    final activeProgress = activeTotal == 0 ? 0.0 : activeDone / activeTotal;

    final bottomPad = MediaQuery.paddingOf(context).bottom + 100;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: MaxWidth(
          maxWidth: 1000,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StudioPageHeader(
                  title: trFill(context, 'Welcome, {name}!', {'name': name}),
                  subtitle: tr(context, 'Learn, Create & Build'),
                  showNotifications: true,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 18),
                _ProgressStrip(
                  progress: activeProgress,
                  completed: activeDone,
                  total: activeTotal,
                  onContinue: () => _openContinue(context, continuePath),
                ),
                const SizedBox(height: 16),
                _StatsRow(
                  streakDays: student?.streakDays ?? 0,
                  lessonsCompleted: lessonsCompleted,
                  points: student?.totalPoints ?? 0,
                  overallProgress: overallProgress,
                ),
                const SizedBox(height: 26),
                StudioSectionHeader(
                  title: tr(context, 'Learn'),
                  actionLabel: tr(context, 'View all'),
                  onAction: () => context.go('/learn'),
                ),
                const SizedBox(height: 14),
                _TileGrid(items: _TileGrid.learnItems(context)),
                const SizedBox(height: 26),
                StudioSectionHeader(title: tr(context, 'MY PATHS')),
                const SizedBox(height: 14),
                _ContinueLearningCard(
                  path: continuePath,
                  onTap: () => _openContinue(context, continuePath),
                ),
                const SizedBox(height: 26),
                StudioSectionHeader(title: tr(context, 'CREATE')),
                const SizedBox(height: 14),
                _TileGrid(items: _TileGrid.createItems(context)),
                const SizedBox(height: 26),
                StudioSectionHeader(title: tr(context, 'MORE')),
                const SizedBox(height: 14),
                _TileGrid(items: _TileGrid.moreItems(context)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static ParsedPath? _pickContinuePath(List<ParsedPath> paths) {
    if (paths.isEmpty) return null;
    final inProgress = paths.where((p) => p.progressFraction < 1).toList();
    if (inProgress.isEmpty) return paths.first;
    inProgress.sort((a, b) => b.completedLessons.compareTo(a.completedLessons));
    return inProgress.first;
  }

  static void _openContinue(BuildContext context, ParsedPath? path) {
    if (path == null) {
      context.go('/learn');
      return;
    }
    context.push('/path/${Uri.encodeComponent(path.topic)}');
  }
}

/// Compact progress strip that replaced the tall journey card.
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.progress,
    required this.completed,
    required this.total,
    required this.onContinue,
  });

  final double progress;
  final int completed;
  final int total;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    // With no active path there is no progress to report, so the ring and the
    // "0 / 0 lessons" line give way to a plain prompt to start one.
    final hasPath = total > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ac.isDark
              ? const [Color(0xFF1A2750), Color(0xFF131E42)]
              : const [Color(0xFFEAF1FE), Color(0xFFF7F5FF)],
        ),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: ac.isDark ? 0.28 : 0.14),
        ),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Row(
        children: [
          if (hasPath)
            _ProgressRing(progress: progress)
          else
            const StudioIconChip(
              icon: Icons.rocket_launch_rounded,
              size: 46,
              radius: 15,
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasPath
                      ? tr(context, 'Your progress')
                      : tr(context, 'Start a learning path'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ac.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasPath
                      ? trFill(context, '{done} / {total} lessons', {
                          'done': '$completed',
                          'total': '$total',
                        })
                      : tr(context, 'What would you like to do today?'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Saira',
                    fontSize: hasPath ? 17 : 15,
                    fontWeight: FontWeight.w700,
                    color: ac.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Icon-only: a labelled pill leaves the title too little room once
          // the label is translated into a longer language.
          Tooltip(
            message: hasPath
                ? tr(context, 'Continue Learning')
                : tr(context, 'Start a learning path'),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onContinue,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryButtonGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.32),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          Text(
            '${(progress.clamp(0.0, 1.0) * 100).round()}%',
            style: TextStyle(
              fontFamily: 'Saira',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.streakDays,
    required this.lessonsCompleted,
    required this.points,
    required this.overallProgress,
  });

  final int streakDays;
  final int lessonsCompleted;
  final int points;
  final double overallProgress;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _Stat(
        icon: Icons.local_fire_department_rounded,
        color: AppColors.accentOrange,
        value: '$streakDays',
        label: tr(context, 'Day Streak'),
      ),
      _Stat(
        icon: Icons.check_circle_rounded,
        color: AppColors.accentGreen,
        value: '$lessonsCompleted',
        label: tr(context, 'Lessons Completed'),
      ),
      _Stat(
        icon: Icons.star_rounded,
        color: AppColors.accentBlue,
        value: '$points',
        label: tr(context, 'Points'),
      ),
      _Stat(
        icon: Icons.trending_up_rounded,
        color: AppColors.accentViolet,
        value: '${(overallProgress * 100).round()}%',
        label: tr(context, 'Overall Progress'),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _StatCard(stat: stats[i])),
        ],
      ],
    );
  }
}

class _Stat {
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            stat.color.withValues(alpha: ac.isDark ? 0.20 : 0.13),
            ac.surface,
          ],
        ),
        border: Border.all(
          color: stat.color.withValues(alpha: ac.isDark ? 0.30 : 0.16),
        ),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Column(
        children: [
          StudioIconChip(
            icon: stat.icon,
            color: stat.color,
            size: 32,
            radius: 11,
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              style: TextStyle(
                fontFamily: 'Saira',
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: ac.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: ac.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

/// The three home sections. CREATE and MORE carry eight destinations
/// (`/sitechat`, `/weblab`, `/pythonlab`, `/applab`, `/projects`,
/// `/achievements`, `/certificates`, `/settings`) that have no bottom-nav tab,
/// so dropping them would make those screens drawer-only.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.items});

  final List<_TileItem> items;

  static List<_TileItem> learnItems(BuildContext context) => [
    _TileItem(
      title: tr(context, 'Subjects'),
      subtitle: tr(context, 'Explore your courses'),
      icon: Icons.auto_stories_rounded,
      color: AppColors.accentBlue,
      route: '/learn',
    ),
    _TileItem(
      title: tr(context, 'Practice'),
      subtitle: tr(context, 'Sharpen your skills'),
      icon: Icons.fact_check_rounded,
      color: AppColors.accentGreen,
      route: '/practice',
    ),
    _TileItem(
      title: tr(context, 'AI Chat'),
      subtitle: tr(context, 'Get instant help'),
      icon: Icons.auto_awesome_rounded,
      color: AppColors.accentViolet,
      route: '/chat',
    ),
    _TileItem(
      title: tr(context, 'Teach'),
      subtitle: tr(context, 'Share your knowledge'),
      icon: Icons.school_rounded,
      color: AppColors.accentTeal,
      route: '/teach',
    ),
  ];

  static List<_TileItem> createItems(BuildContext context) => [
    _TileItem(
      title: tr(context, 'Website'),
      icon: Icons.web_rounded,
      color: AppColors.brandCyan,
      route: '/sitechat',
    ),
    _TileItem(
      title: tr(context, 'Web Lab'),
      icon: Icons.code_rounded,
      color: AppColors.brandCyan,
      route: '/weblab',
    ),
    _TileItem(
      title: tr(context, 'Python*'),
      icon: Icons.terminal_rounded,
      color: AppColors.accentDeep,
      route: '/pythonlab',
    ),
    _TileItem(
      title: tr(context, 'App Lab*'),
      icon: Icons.phone_android_rounded,
      color: AppColors.accentBlue,
      route: '/applab',
    ),
  ];

  static List<_TileItem> moreItems(BuildContext context) => [
    _TileItem(
      title: tr(context, 'Projects'),
      icon: Icons.folder_rounded,
      color: AppColors.brandCyan,
      route: '/projects',
    ),
    _TileItem(
      title: tr(context, 'Certs'),
      icon: Icons.workspace_premium_rounded,
      color: AppColors.accentViolet,
      route: '/certificates',
    ),
    _TileItem(
      title: tr(context, 'Settings'),
      icon: Icons.settings_rounded,
      color: AppColors.accentSlate,
      route: '/settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(
      context,
    ).width.clamp(0.0, 1000.0).toDouble();
    final cols = adaptiveColumns(width, min: 2, max: 5, itemWidth: 200);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Subtitle-less tiles need less vertical room.
        childAspectRatio: items.any((i) => i.subtitle != null) ? 1.32 : 2.1,
      ),
      itemBuilder: (context, i) => _Tile(item: items[i]),
    );
  }
}

class _TileItem {
  const _TileItem({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String title;

  /// Optional — the CREATE and MORE tiles are label-only, so the tile drops
  /// the subtitle line rather than inventing filler for it.
  final String? subtitle;
  final IconData icon;
  final Color color;
  final String route;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item});

  final _TileItem item;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final compact = item.subtitle == null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Material(
        color: ac.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(item.route),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: item.color.withValues(alpha: ac.isDark ? 0.30 : 0.16),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  item.color.withValues(alpha: ac.isDark ? 0.20 : 0.13),
                  item.color.withValues(alpha: ac.isDark ? 0.06 : 0.02),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -22,
                  top: -22,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.color.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                compact ? _compactBody(ac) : _fullBody(ac),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactBody(AppColors ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          StudioIconChip(
            icon: item.icon,
            color: item.color,
            size: 36,
            radius: 12,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Saira',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ac.textPrimary,
              ),
            ),
          ),
          Icon(Icons.arrow_forward_rounded, size: 17, color: item.color),
        ],
      ),
    );
  }

  Widget _fullBody(AppColors ac) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StudioIconChip(
            icon: item.icon,
            color: item.color,
            size: 38,
            radius: 13,
          ),
          const Spacer(),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Saira',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ac.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: ac.textSecondary),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 17, color: item.color),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinueLearningCard extends StatelessWidget {
  const _ContinueLearningCard({required this.path, required this.onTap});

  final ParsedPath? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final title = path?.title ?? tr(context, 'Start a learning path');
    final subtitle = path == null
        ? tr(context, 'Pick a subject and begin your first lesson')
        : _chapterLabel(context, path!);
    final done = path?.completedLessons ?? 0;
    // Report the path's real lesson count rather than substituting a made-up
    // denominator, which made an empty path read "0 / 5 lessons".
    final total = path?.totalLessons ?? 0;
    final progress = total == 0 ? 0.0 : done / total;
    final tag = path?.topic ?? tr(context, 'Learn');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Material(
        color: ac.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ac.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  _PathThumbnail(tag: tag),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Saira',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: ac.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: ac.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 7,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          trFill(context, '{done} / {total} lessons', {
                            'done': '$done',
                            'total': '$total',
                          }),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ac.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryButtonGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.32),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _chapterLabel(BuildContext context, ParsedPath path) {
    String label(int index, String title) => trFill(
      context,
      'Chapter {number}: {title}',
      {'number': '${index + 1}', 'title': title},
    );

    for (var u = 0; u < path.units.length; u++) {
      final unit = path.units[u];
      for (var l = 0; l < unit.lessons.length; l++) {
        if (!unit.lessons[l].isCompleted) return label(u, unit.title);
      }
    }
    if (path.units.isEmpty) return path.description;
    return label(path.units.length - 1, path.units.last.title);
  }
}

class _PathThumbnail extends StatelessWidget {
  const _PathThumbnail({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandCyan, AppColors.brandViolet],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -14,
            top: -14,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          const Positioned(
            left: 10,
            top: 12,
            child: Icon(Icons.route_rounded, size: 22, color: Colors.white),
          ),
          Positioned(
            left: 10,
            right: 8,
            bottom: 10,
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
