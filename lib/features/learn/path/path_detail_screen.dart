import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_locale.dart';
import '../../../shared/widgets/responsive.dart';
import '../../../shared/widgets/studio_page.dart';
import 'path_models.dart';
import 'path_provider.dart';

class PathDetailScreen extends ConsumerStatefulWidget {
  const PathDetailScreen({super.key, required this.topic});
  final String topic;

  @override
  ConsumerState<PathDetailScreen> createState() => _PathDetailScreenState();
}

class _PathDetailScreenState extends ConsumerState<PathDetailScreen> {
  int _expandedUnit = 0;

  @override
  Widget build(BuildContext context) {
    final pathAsync = ref.watch(pathByTopicProvider(widget.topic));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: widget.topic,
        subtitle: tr(context, 'Your learning path'),
        showBack: true,
        showMenu: false,
      ),
      body: pathAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (row) {
          if (row == null) {
            return _GeneratingView(
              topic: widget.topic,
              onGenerated: () =>
                  ref.invalidate(pathByTopicProvider(widget.topic)),
            );
          }
          final parsed = parsedFromRow(row);
          return _PathContent(
            pathId: row.id,
            parsed: parsed,
            expandedUnit: _expandedUnit,
            onUnitTap: (i) => setState(() => _expandedUnit = i),
            onLessonTap: (unitIndex, lessonIndex, lesson) => _openLesson(
              context,
              parsed,
              row.id,
              unitIndex,
              lessonIndex,
              lesson,
            ),
          );
        },
      ),
    );
  }

  void _openLesson(
    BuildContext context,
    ParsedPath parsed,
    int pathId,
    int unitIndex,
    int lessonIndex,
    PathLesson lesson,
  ) async {
    // Navigate to Learn screen with the lesson topic pre-filled, then mark complete on return
    final topic = '${lesson.title} (${widget.topic})';
    await context.push('/learn?topic=${Uri.encodeComponent(topic)}');

    if (!mounted) return;
    await ref
        .read(pathNotifierProvider.notifier)
        .completeLesson(
          pathId: pathId,
          parsed: parsed,
          unitIndex: unitIndex,
          lessonIndex: lessonIndex,
        );
  }
}

// ── Path content ──────────────────────────────────────────────────────────────

class _PathContent extends StatelessWidget {
  const _PathContent({
    required this.pathId,
    required this.parsed,
    required this.expandedUnit,
    required this.onUnitTap,
    required this.onLessonTap,
  });

  final int pathId;
  final ParsedPath parsed;
  final int expandedUnit;
  final void Function(int) onUnitTap;
  final void Function(int unitIndex, int lessonIndex, PathLesson) onLessonTap;

  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _PathHeader(parsed: parsed)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _UnitTile(
                unit: parsed.units[i],
                unitIndex: i,
                isExpanded: expandedUnit == i,
                onTap: () => onUnitTap(i),
                onLessonTap: (li, lesson) => onLessonTap(i, li, lesson),
              ),
              childCount: parsed.units.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _PathHeader extends StatelessWidget {
  const _PathHeader({required this.parsed});
  final ParsedPath parsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(parsed.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            parsed.description,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: parsed.progressFraction,
                    minHeight: 8,
                    backgroundColor: Theme.of(context).dividerColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.learnColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${parsed.completedLessons}/${parsed.totalLessons} lessons',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.unit,
    required this.unitIndex,
    required this.isExpanded,
    required this.onTap,
    required this.onLessonTap,
  });

  final PathUnit unit;
  final int unitIndex;
  final bool isExpanded;
  final VoidCallback onTap;
  final void Function(int lessonIndex, PathLesson) onLessonTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: unit.isComplete
                        ? AppColors.teachColor.withValues(alpha: 0.12)
                        : AppColors.learnColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    unit.isComplete ? Icons.check : Icons.view_module,
                    size: 16,
                    color: unit.isComplete
                        ? AppColors.teachColor
                        : AppColors.learnColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unit ${unitIndex + 1} · ${unit.title}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${unit.completedCount}/${unit.lessons.length} done',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).hintColor,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ...unit.lessons.asMap().entries.map(
            (e) => _LessonRow(
              lesson: e.value,
              lessonIndex: e.key,
              onTap: () => onLessonTap(e.key, e.value),
            ),
          ),
      ],
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.lesson,
    required this.lessonIndex,
    required this.onTap,
  });

  final PathLesson lesson;
  final int lessonIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(
          left: 64,
          right: 20,
          top: 14,
          bottom: 14,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lesson.isCompleted
                    ? AppColors.teachColor
                    : Theme.of(context).dividerColor,
              ),
              child: Icon(
                lesson.isCompleted ? Icons.check : Icons.play_arrow,
                size: 13,
                color: lesson.isCompleted
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lesson.title,
                style: TextStyle(
                  color: lesson.isCompleted
                      ? Theme.of(context).hintColor
                      : Theme.of(context).colorScheme.onSurface,
                  decoration: lesson.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  height: 1.4,
                ),
              ),
            ),
            if (!lesson.isCompleted)
              Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: Theme.of(context).hintColor,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Generating view (first open, no path yet) ─────────────────────────────────

class _GeneratingView extends ConsumerWidget {
  const _GeneratingView({required this.topic, required this.onGenerated});
  final String topic;
  final VoidCallback onGenerated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                color: AppColors.learnColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.route,
                color: AppColors.learnColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Build a learning path for\n"$topic"?',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'A 4-unit, 12-lesson curriculum will be tailored for you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () async {
                await ref
                    .read(pathNotifierProvider.notifier)
                    .generatePath(topic);
                onGenerated();
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate my path'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/learn'),
              child: const Text('Skip — just chat'),
            ),
          ],
        ),
      ),
    );
  }
}
