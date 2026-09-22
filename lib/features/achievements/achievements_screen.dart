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
        iconColor: AppColors.accentOrange,
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
        final earnedCount =
            earnedIds.where((id) => badgeById(id) != null).length;
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                  child: StudioSectionHeader(title: tr(context, 'Badges')),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StudioCard(
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
    final ac = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Saira',
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 19,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            trFill(context, '{earned} of {total} badges earned',
                {'earned': '$earned', 'total': '$total'}),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total > 0 ? earned / total : 0,
              minHeight: 7,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeaderStat(
                  icon: Icons.stars_rounded,
                  iconColor: const Color(0xFFFFD166),
                  value: '${student.totalPoints}',
                  label: tr(context, 'points'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderStat(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFFFB27A),
                  value: '${student.streakDays}',
                  label: tr(context, 'day streak'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
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
    final ac = AppColors.of(context);
    final labelColor = isEarned ? def.color : ac.textHint;

    return StudioCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      // Locked tiles take a muted slate wash so they stay legibly "not yet"
      // against a white page, where an untinted card would vanish.
      accent: isEarned ? def.color : AppColors.accentSlate,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(def.icon, size: 34, color: labelColor),
          const SizedBox(height: 8),
          Text(
            tr(context, def.name),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: labelColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            isEarned && earnedAt != null
                ? _fmt(earnedAt!)
                : tr(context, def.description),
            style: TextStyle(
              fontSize: 11,
              color: isEarned ? ac.textSecondary : ac.textHint,
              fontStyle: isEarned ? FontStyle.normal : FontStyle.italic,
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
                color: def.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('+${def.points} pts',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
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
