import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Projects'),
        subtitle: tr(context, 'Your saved creations'),
        icon: Icons.folder_rounded,
        iconColor: const Color(0xFF3BAFD4),
        actions: [
          StudioHeaderIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New project',
            onTap: () => context.go('/create'),
          ),
        ],
      ),
      body: studentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (student) {
          if (student == null) {
            return const Center(child: Text('No student profile found.'));
          }
          return _ProjectsList(studentId: student.id);
        },
      ),
    );
  }
}

class _ProjectsList extends ConsumerWidget {
  const _ProjectsList({required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(studentProjectsProvider(studentId));

    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (projects) {
        if (projects.isEmpty) {
          return _EmptyProjects();
        }

        return MaxWidth(
          maxWidth: 900,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ProjectCard(project: projects[i]),
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final StudentProject project;

  static const _typeIcons = <String, IconData>{
    'essay': Icons.article,
    'business_plan': Icons.trending_up,
    'experiment': Icons.science,
    'story': Icons.menu_book,
    'code_plan': Icons.code,
    'other': Icons.lightbulb,
  };

  static const _typeColors = <String, Color>{
    'essay': AppColors.learnColor,
    'business_plan': AppColors.businessColor,
    'experiment': AppColors.academicColor,
    'story': AppColors.lifeSkillsColor,
    'code_plan': AppColors.technologyColor,
    'other': AppColors.createColor,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcons[project.projectType] ?? Icons.lightbulb;
    final color = _typeColors[project.projectType] ?? AppColors.createColor;
    final label = project.projectType.replaceAll('_', ' ');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          project.title,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              label[0].toUpperCase() + label.substring(1),
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            Text(
              _fmt(project.updatedAt),
              style:
                  TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
            ),
          ],
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: project.status == 'complete'
                ? AppColors.teachColor.withValues(alpha: 0.1)
                : AppColors.practiceColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            project.status == 'complete' ? 'Done' : 'In progress',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: project.status == 'complete'
                  ? AppColors.teachColor
                  : AppColors.practiceColor,
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _EmptyProjects extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.createColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.folder_open,
                  color: AppColors.createColor, size: 32),
            ),
            const SizedBox(height: 18),
            Text('No projects yet',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Go to Create mode to build your first project — an essay, business plan, experiment, or anything you can imagine.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/create'),
              icon: const Icon(Icons.add),
              label: const Text('Start a project'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
