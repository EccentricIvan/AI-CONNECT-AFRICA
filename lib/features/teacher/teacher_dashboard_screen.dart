import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

String _shortWhen(DateTime dt) {
  final local = dt.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$m/$d $h:$min';
}

final _allStudentsForTeacherProvider = FutureProvider<List<Student>>((ref) {
  if (kIsWeb) return Future.value(const []);
  return ref.watch(dbProvider).studentDao.getAllStudents();
});

/// Classroom overview for teachers on a shared device.
class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(_allStudentsForTeacherProvider);
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: 'Teacher',
        subtitle: 'Classroom progress overview',
        icon: Icons.groups_rounded,
        iconColor: const Color(0xFF3B8FE8),
        actions: [
          StudioHeaderIconButton(
            tooltip: 'Refresh',
            icon: Icons.refresh_rounded,
            onTap: () => ref.invalidate(_allStudentsForTeacherProvider),
          ),
        ],
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: studentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load students: $e')),
          data: (students) {
            if (students.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups_outlined, size: 48, color: colors.textHint),
                      const SizedBox(height: 16),
                      Text(
                        'No student profiles yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When learners complete onboarding on this device, '
                        'their progress will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  '${students.length} learner${students.length == 1 ? '' : 's'} on this device',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                ...students.map(
                  (s) => _StudentCard(
                    student: s,
                    onOpen: () => context.push('/teacher/${s.id}'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.onOpen});

  final Student student;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final when = _shortWhen(student.lastActiveAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (student.grade != null && student.grade!.isNotEmpty)
                            student.grade!,
                          '${student.totalPoints} pts',
                          'Active $when',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TeacherStudentDetailScreen extends ConsumerWidget {
  const TeacherStudentDetailScreen({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(_allStudentsForTeacherProvider);
    final sessionsAsync = ref.watch(recentSessionsProvider(studentId));
    final progressAsync = ref.watch(topicProgressProvider(studentId));
    final colors = AppColors.of(context);

    Student? student;
    final list = studentsAsync.valueOrNull;
    if (list != null) {
      for (final s in list) {
        if (s.id == studentId) {
          student = s;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: student?.name ?? 'Learner',
        subtitle: 'Student progress detail',
        showBack: true,
        showMenu: false,
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (student != null) ...[
              _DetailHeader(student: student),
              const SizedBox(height: 20),
            ],
            Text(
              'Topic progress',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            progressAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load progress: $e'),
              data: (topics) {
                if (topics.isEmpty) {
                  return Text(
                    'No topics studied yet.',
                    style: TextStyle(color: colors.textSecondary),
                  );
                }
                return Column(
                  children: topics
                      .map(
                        (t) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.topic),
                          subtitle: Text('${t.sessionsCount} sessions'),
                          trailing: Text(
                            'Lv ${t.level}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Recent sessions',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            sessionsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load sessions: $e'),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Text(
                    'No chat sessions saved yet.',
                    style: TextStyle(color: colors.textSecondary),
                  );
                }
                return Column(
                  children: sessions.map((s) {
                    final when = _shortWhen(s.sessionAt);
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                        color: colors.surface,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.topic,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${s.highestStage} · ${s.messageCount} messages · $when',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                          if (s.summary.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              s.summary,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
        color: AppColors.primary.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.name,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            [
              if (student.grade != null) 'Grade ${student.grade}',
              '${student.totalPoints} points',
              '${student.streakDays}-day streak',
              'Style: ${student.learningStyle}',
            ].join(' · '),
            style: TextStyle(color: colors.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }
}
