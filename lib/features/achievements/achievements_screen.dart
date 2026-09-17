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

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Achievements'),
        subtitle: tr(context, 'Badges, points & streaks'),
        icon: Icons.emoji_events_rounded,
        iconColor: const Color(0xFFFF8A3D),
      ),
      body: studentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (student) {
          if (student == null) {
            return const Center(child: Text('No student profile found.'));
          }
          return _AchievementsBody(studentId: student.id, student: student);
        },
      ),
    );
  }
}

class _AchievementsBody extends ConsumerWidget {
  const _AchievementsBody({required this.studentId, required this.student});
  final int studentId;
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgesAsync = ref.watch(earnedBadgesProvider(studentId));

    return badgesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (earned) {
        final earnedIds = earned.map((b) => b.badgeId).toSet();
        final earnedCount = earnedIds.length;
        final width =
            MediaQuery.sizeOf(context).width.clamp(0.0, 1000.0).toDouble();
        final cols = adaptiveColumns(width, min: 2, max: 5, itemWidth: 200);

        return MaxWidth(
            maxWidth: 1000,
            child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _StatsHeader(
                student: student,
                earned: earnedCount,
                total: allBadges.length,
              ),
            ),
            const SliverToBoxAdapter(child: _CertificatesLink()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final def = allBadges[i];
                    final isEarned = earnedIds.contains(def.id);
                    return _BadgeTile(
                        def: def,
                        isEarned: isEarned,
                        earnedAt: isEarned
                            ? earned
                                .firstWhere((b) => b.badgeId == def.id)
                                .earnedAt
                            : null);
                  },
                  childCount: allBadges.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }
}

/// Certificates no longer has its own sidebar entry — it lives here, under the
/// badge stats, and opens as a pushed screen with a back button.
class _CertificatesLink extends StatelessWidget {
  const _CertificatesLink();

  static const _color = Color(0xFF7B6CF6);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: InkWell(
        onTap: () => GoRouter.of(context).push('/certificates'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: _color, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'Certificates'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(context, 'Celebrate completed paths'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 15, color: Theme.of(context).hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader(
      {required this.student, required this.earned, required this.total});
  final Student student;
  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$earned of $total badges earned',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? earned / total : 0,
                    minHeight: 7,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Column(
            children: [
              const Icon(Icons.stars, color: Colors.amber, size: 28),
              const SizedBox(height: 4),
              Text(
                '${student.totalPoints}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const Text(
                'points',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile(
      {required this.def, required this.isEarned, this.earnedAt});
  final BadgeDef def;
  final bool isEarned;
  final DateTime? earnedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isEarned
            ? def.color.withValues(alpha: 0.07)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEarned
              ? def.color.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            def.icon,
            size: 36,
            color: isEarned ? def.color : Theme.of(context).hintColor,
          ),
          const SizedBox(height: 8),
          Text(
            def.name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isEarned ? def.color : Theme.of(context).hintColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            isEarned && earnedAt != null
                ? _fmt(earnedAt!)
                : def.description,
            style: TextStyle(
              fontSize: 11,
              color: isEarned ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).hintColor,
              fontStyle:
                  isEarned ? FontStyle.normal : FontStyle.italic,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (isEarned) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: def.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('+${def.points} pts',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: def.color)),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}
