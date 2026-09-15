import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../services/custom_subject_service.dart';
import '../../shared/widgets/localized_text.dart';
import '../../shared/widgets/studio_page.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  static const _icons = <String, IconData>{
    'calculate': Icons.calculate,
    'science': Icons.science,
    'biotech': Icons.biotech,
    'science_outlined': Icons.science_outlined,
    'code': Icons.code,
    'web': Icons.web,
    'phone_android': Icons.phone_android,
    'psychology': Icons.psychology,
    'trending_up': Icons.trending_up,
    'grass': Icons.grass,
    'history_edu': Icons.history_edu,
    'public': Icons.public,
    'menu_book': Icons.menu_book,
    'account_balance': Icons.account_balance,
    'palette': Icons.palette,
  };

  static Color _parseColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(mergedSubjectsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'Learn'),
        subtitle: tr(context, 'Explore your courses'),
        icon: Icons.auto_stories_rounded,
        iconColor: const Color(0xFF3B8FE8),
      ),
      body: subjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading subjects: $e')),
        data: (subjects) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            StudioHeroBanner(
              eyebrow: tr(context, 'Curriculum'),
              title: tr(context, 'Your subjects'),
              body: tr(
                context,
                'Browse courses and keep building skills one lesson at a time.',
              ),
            ),
            const SizedBox(height: 20),
            StudioSectionHeader(title: tr(context, 'All subjects')),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.32,
              ),
              itemCount: subjects.length,
              itemBuilder: (context, i) {
                final s = subjects[i];
                final color = _parseColor(s.color);
                final icon = _icons[s.icon] ?? Icons.menu_book;
                return _SubjectCard(
                  name: s.name,
                  icon: icon,
                  color: color,
                  lessonCount: s.totalLessons,
                  onTap: () => context.push('/learn/subject/${s.id}'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.lessonCount,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final Color color;
  final int lessonCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);

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
              border: Border.all(
                color: color.withValues(alpha: ac.isDark ? 0.30 : 0.16),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: ac.isDark ? 0.20 : 0.13),
                  color.withValues(alpha: ac.isDark ? 0.06 : 0.02),
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
                      color: color.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StudioIconChip(
                        icon: icon,
                        color: color,
                        size: 38,
                        radius: 13,
                      ),
                      const Spacer(),
                      LocalizedText(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Saira',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ac.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              trFill(
                                context,
                                '{count} lessons',
                                {'count': '$lessonCount'},
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: ac.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: color,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
