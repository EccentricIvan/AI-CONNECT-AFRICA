import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/sync/progress_report.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_models.dart';
import '../../services/custom_subject_service.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/studio_page.dart';
import 'class_providers.dart';

/// Latest reports from members' devices for one class, live from SQLite.
final memberReportsProvider = StreamProvider.autoDispose
    .family<List<({ProgressReport report, String receivedAt})>, String>(
      (ref, classUuid) =>
          ref.watch(dbProvider).classSyncDao.watchMemberReports(classUuid),
    );

/// How a class is doing, from its members' own devices: each learner's
/// latest report, as sent when they last synced with this teacher device.
/// Stored on this device, so it shows whether or not sharing is on.
class ClassProgressPanel extends ConsumerWidget {
  const ClassProgressPanel({super.key, required this.group});

  final ClassGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final uuid = group.groupUuid;
    final rows = uuid == null
        ? const <({ProgressReport report, String receivedAt})>[]
        : ref.watch(memberReportsProvider(uuid)).valueOrNull ?? const [];

    final names = {
      for (final s
          in ref.watch(mergedSubjectsProvider).valueOrNull ?? const <Subject>[])
        s.id: s.name,
    };
    final levels = [for (final r in rows) ?r.report.meanLevel];
    final classMean = levels.isEmpty
        ? null
        : (levels.reduce((a, b) => a + b) / levels.length).round();

    return StudioCard(
      accent: AppColors.accentGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Class progress · ${classLabel(group)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            rows.isEmpty
                ? 'Nothing yet. Each student’s progress arrives here when their '
                      'device syncs with you.'
                : '${rows.length} learner${rows.length == 1 ? '' : 's'} reported'
                      '${classMean == null ? '' : ' · class mastery $classMean%'}',
            style: TextStyle(fontSize: 12, color: ac.textSecondary),
          ),
          for (final r in rows)
            _MemberRow(
              report: r.report,
              at: r.receivedAt,
              subjectName: (id) => names[id] ?? id.replaceAll('_', ' '),
            ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.report,
    required this.at,
    required this.subjectName,
  });

  final ProgressReport report;
  final String at;
  final String Function(String id) subjectName;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final r = report;
    final accuracy = r.practiceAttempted == 0
        ? null
        : (100 * r.practiceCorrect / r.practiceAttempted).round();
    final weak = [
      for (final t in r.topics)
        if (t.level < 50) t.topic,
    ];
    final facts = [
      if (r.meanLevel != null) 'mastery ${r.meanLevel}%',
      '${r.lessonsCompleted} lessons',
      if (accuracy != null) 'practice $accuracy% right',
      '${r.points} pts',
      if (r.streakDays > 0) '${r.streakDays}-day streak',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: ac.textPrimary,
                  ),
                ),
              ),
              Text(
                'synced ${_when(at)}',
                style: TextStyle(fontSize: 11, color: ac.textHint),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            facts.join(' · '),
            style: TextStyle(fontSize: 12, color: ac.textSecondary),
          ),
          if (r.enrolled.isNotEmpty)
            Text(
              'Takes: ${r.enrolled.map(subjectName).join(', ')}',
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
          if (weak.isNotEmpty || r.weaknesses.isNotEmpty)
            Text(
              'Needs help: ${{...weak.take(3), ...r.weaknesses.take(2)}.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.accentOrange,
              ),
            ),
          if (r.topics.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in r.topics.take(8))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${t.topic} ${t.level}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _when(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
