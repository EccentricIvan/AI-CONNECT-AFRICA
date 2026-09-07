import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_provider.dart';
import '../../curriculum/curriculum_models.dart';
import '../../shared/widgets/studio_page.dart';

class AppDevLabScreen extends ConsumerWidget {
  const AppDevLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final curriculum = ref.watch(curriculumServiceProvider);

    return FutureBuilder(
      future: curriculum.load('app_development'),
      builder: (context, snapshot) {
        final subject = snapshot.data;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.phone_android, size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text('App Dev Lab'),
              ],
            ),
            actions: const [StudioDrawerButton()],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8D4A8)),
                ),
                child: const Text(
                  'Concepts curriculum — this lab teaches app ideas. '
                  'There is no build/run IDE yet.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
              Expanded(
                child: subject == null
                    ? const Center(child: CircularProgressIndicator())
                    : _AppDevContent(subject: subject),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppDevContent extends StatelessWidget {
  const _AppDevContent({required this.subject});
  final Subject subject;

  static const _unitIcons = [
    Icons.lightbulb,
    Icons.widgets,
    Icons.storage,
    Icons.rocket_launch,
  ];

  static const _unitColors = [
    AppColors.primary,
    AppColors.practiceColor,
    AppColors.createColor,
    AppColors.teachColor,
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.phone_android, size: 36, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'Learn App Development',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${subject.totalLessons} lessons covering app concepts, '
                  'UI design, data management, and publishing.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Units
          ...subject.units.asMap().entries.map((entry) {
            final ui = entry.key;
            final unit = entry.value;
            final color = _unitColors[ui % _unitColors.length];
            final icon = _unitIcons[ui % _unitIcons.length];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unit ${ui + 1}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                          ),
                          Text(
                            unit.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...unit.lessons.asMap().entries.map((le) {
                  final li = le.key;
                  final lesson = le.value;
                  return Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 8),
                    child: InkWell(
                      onTap: () => context.push(
                        '/learn/subject/app_development/lesson/$ui/$li',
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(
                                child: Text(
                                  '${li + 1}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                lesson.title,
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: Theme.of(context).hintColor),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],
            );
          }),
        ],
      ),
    );
  }
}
