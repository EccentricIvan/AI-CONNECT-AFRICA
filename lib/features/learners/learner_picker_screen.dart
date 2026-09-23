import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../teacher/class_providers.dart';
import 'add_learner_dialog.dart';
import 'learner_switcher.dart';

/// "Who's learning?" — hands a shared device to another learner.
class LearnerPickerScreen extends ConsumerStatefulWidget {
  const LearnerPickerScreen({super.key});

  @override
  ConsumerState<LearnerPickerScreen> createState() =>
      _LearnerPickerScreenState();
}

class _LearnerPickerScreenState extends ConsumerState<LearnerPickerScreen> {
  bool _busy = false;

  Future<void> _switchTo(int id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(learnerSwitcherProvider).switchTo(id);
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final id = await showAddLearnerDialog(context, ref);
    if (id != null && mounted) await _switchTo(id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final learners = ref.watch(allLearnersProvider);
    final classes = {
      for (final c in ref.watch(classGroupsProvider).valueOrNull ??
          const <ClassGroup>[])
        c.id: c,
    };
    final activeId = ref.watch(activeStudentProvider).valueOrNull?.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, "Who's learning?"),
        subtitle: tr(context, 'Pick your name to continue'),
        icon: Icons.switch_account_rounded,
        iconColor: AppColors.primary,
        showBack: true,
        showMenu: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr(context, 'Add learner')),
      ),
      body: MaxWidth(
        maxWidth: 640,
        child: learners.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              if (_busy) const LinearProgressIndicator(),
              for (final s in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    enabled: !_busy,
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        if (s.classGroupId != null &&
                            classes[s.classGroupId] != null)
                          classLabel(classes[s.classGroupId]!),
                        if (s.grade != null && s.grade!.isNotEmpty) s.grade!,
                      ].join(' · '),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    trailing: s.id == activeId
                        ? Chip(label: Text(tr(context, 'Current')))
                        : const Icon(Icons.chevron_right),
                    onTap: s.id == activeId
                        ? () => context.go('/')
                        : () => _switchTo(s.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
