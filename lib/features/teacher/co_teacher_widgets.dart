import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/sync/class_share_server.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_models.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../services/custom_subject_service.dart';
import '../../shared/widgets/studio_page.dart';
import 'class_providers.dart';

/// Root device: the co-teachers of [group] and the subjects each teaches,
/// with Invite (needs [server] running — codes live on the server) and
/// Revoke.
class CoTeachersCard extends ConsumerWidget {
  const CoTeachersCard({super.key, required this.group, required this.server});

  final ClassGroup group;
  final ClassShareServer? server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final coTeachers =
        ref.watch(coTeachersProvider(group.groupUuid!)).valueOrNull ??
        const <ClassCoTeacher>[];
    final names = subjectNames(ref);

    return StudioCard(
      accent: AppColors.accentBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Teachers on this class',
            style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
          ),
          if (coTeachers.isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Only you',
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
          ],
          for (final t in coTeachers)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.school_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, style: TextStyle(color: ac.textPrimary)),
                        Text(
                          _decode(t.subjectIdsJson).map(names).join(', '),
                          style: TextStyle(
                            fontSize: 12,
                            color: ac.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _revoke(context, ref, t),
                    child: const Text('Revoke'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: server?.isRunning == true
                ? () => _invite(context, ref, names)
                : null,
            icon: const Icon(Icons.person_add_alt_rounded, size: 18),
            label: const Text('Invite a co-teacher'),
          ),
          if (server?.isRunning != true)
            Text(
              'Available while sharing',
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
        ],
      ),
    );
  }

  static List<String> _decode(String json) => [
    for (final s in jsonDecode(json) as List)
      if (s is String) s,
  ];

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    ClassCoTeacher t,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${t.name}?'),
        content: const Text('Their subjects return to you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(dbProvider);
    final fresh = await db.classSyncDao.ownedByUuid(group.groupUuid!);
    if (fresh == null) return;
    await db.coTeacherDao.revokeCoTeacher(fresh, t.publicKey);
  }

  Future<void> _invite(
    BuildContext context,
    WidgetRef ref,
    String Function(String) names,
  ) async {
    final db = ref.read(dbProvider);
    final taken = await db.coTeacherDao.allocatedSubjects(group.groupUuid!);
    final subjects = [
      for (final s
          in ref.read(mergedSubjectsProvider).valueOrNull ?? const <Subject>[])
        if (!taken.contains(s.id)) s,
    ];
    if (!context.mounted) return;
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every subject is already given to a co-teacher.'),
        ),
      );
      return;
    }
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final chosen = <String>{};
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Subjects the co-teacher will teach'),
            content: SizedBox(
              width: 380,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in subjects)
                    CheckboxListTile(
                      value: chosen.contains(s.id),
                      title: Text(s.name),
                      onChanged: (on) => setState(
                        () => on == true
                            ? chosen.add(s.id)
                            : chosen.remove(s.id),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, chosen.toList()),
                child: const Text('Make invite code'),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || picked.isEmpty) return;
    final code = await server?.openCoTeacherInviteCode(
      group,
      subjectIds: picked,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Co-teacher invite code'),
        content: code == null
            ? const Text(
                'One of those subjects is already assigned. Try again.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SelectableText(
                        code,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          fontFamily: 'monospace',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: code)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${picked.map(names).join(', ')} · valid for 15 minutes',
                  ),
                ],
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// Subject id → the name a teacher gave it ("Web Development"), falling
/// back to a tidied id.
String Function(String) subjectNames(WidgetRef ref) {
  final names = {
    for (final s
        in ref.watch(mergedSubjectsProvider).valueOrNull ?? const <Subject>[])
      s.id: s.name,
  };
  return (id) =>
      names[id] ??
      id
          .split('_')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
}
