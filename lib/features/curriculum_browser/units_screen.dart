import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../ai_core/tutor/programming_topic.dart';
import '../../core/theme/app_colors.dart';
import '../../services/custom_subject_service.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/localized_text.dart';
import '../../shared/widgets/studio_page.dart';

class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // subjectByIdProvider, not CurriculumService.load, so a subject the
    // teacher created opens here too. Bundled subjects resolve exactly as
    // before; a custom one is built from the material uploaded into it.
    final subjectAsync = ref.watch(subjectByIdProvider(subjectId));

    return Builder(
      builder: (context) {
        final subject = subjectAsync.valueOrNull;
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

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: StudioAppBar(
            title: subject.name,
            subtitle: trFill(
              context,
              '{count} lessons',
              {'count': '${subject.totalLessons}'},
            ),
            showBack: true,
            showMenu: false,
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: subject.units.length +
                (isProgrammingSubjectId(subjectId) ? 1 : 0),
            itemBuilder: (context, index) {
              if (isProgrammingSubjectId(subjectId) && index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      '/chat?topic=${Uri.encodeComponent(subject.name)}'
                      '&subject=${Uri.encodeComponent(subjectId)}',
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(tr(context, 'Chat about this subject')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                );
              }
              final unitIndex =
                  isProgrammingSubjectId(subjectId) ? index - 1 : index;
              final unit = subject.units[unitIndex];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: unitIndex > 0 ? 24 : 0, bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: LocalizedText(
                            unit.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            trFill(
                              context,
                              '{count} topics',
                              {'count': '${unit.lessons.length}'},
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...unit.lessons.asMap().entries.map((entry) {
                    final lessonIndex = entry.key;
                    final lesson = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => context.push(
                          '/learn/subject/$subjectId/lesson/$unitIndex/$lessonIndex',
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${lessonIndex + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LocalizedText(
                                  lesson.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context).hintColor,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
