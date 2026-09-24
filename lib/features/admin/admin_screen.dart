import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/app_info_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../teacher/teacher_pin.dart';

/// Admin dashboard — device, user, and update management.
/// Admins manage the platform; they have no learning features here.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelAsync = ref.watch(modelInfoProvider);
    final studentsAsync = ref.watch(_allStudentsProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);
    final pinSetAsync = ref.watch(_pinSetProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'Admin dashboard'),
        subtitle: tr(context, 'Device & learner management'),
        icon: Icons.admin_panel_settings_rounded,
        iconColor: AppColors.accentSlate,
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Device ───────────────────────────────────────────────────
            const _SectionTitle('Device'),
            _InfoCard(
              children: [
                _InfoRow(
                  icon: Icons.computer,
                  label: 'Platform',
                  value:
                      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                ),
                _InfoRow(
                  icon: Icons.apps,
                  label: 'App version',
                  value: packageInfoAsync.when(
                    data: (info) => 'Version ${info.version} (build ${info.buildNumber})',
                    loading: () => 'Loading…',
                    error: (_, __) => 'Unknown',
                  ),
                ),
                const _InfoRow(
                  icon: Icons.wifi_off,
                  label: 'Network',
                  value: 'Fully offline — no internet used',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── AI Model ─────────────────────────────────────────────────
            const _SectionTitle('AI Model'),
            modelAsync.when(
              loading: () => const _InfoCard(
                children: [ListTile(title: Text('Checking model…'))],
              ),
              error: (e, _) => _InfoCard(
                children: [ListTile(title: Text('Model check failed: $e'))],
              ),
              data: (info) => _InfoCard(
                children: [
                  _InfoRow(
                    icon: Icons.memory,
                    label: 'Qwen2.5-Coder 1.5B (tutor + code)',
                    value: info.isReady
                        ? 'Installed · ${info.platform ?? ''}'
                        : 'Not installed',
                    valueColor: info.isReady
                        ? AppColors.teachColor
                        : Colors.orange,
                  ),
                  if (info.isReady && info.sizeBytes != null)
                    _InfoRow(
                      icon: Icons.sd_storage,
                      label: 'Model size',
                      value:
                          '${(info.sizeBytes! / (1024 * 1024)).toStringAsFixed(0)} MB',
                    ),
                  if (info.path != null)
                    _InfoRow(
                      icon: Icons.folder,
                      label: 'Model path',
                      value: info.path!,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Users ────────────────────────────────────────────────────
            const _SectionTitle('Student Profiles'),
            studentsAsync.when(
              loading: () => const _InfoCard(
                children: [ListTile(title: Text('Loading students…'))],
              ),
              error: (e, _) =>
                  _InfoCard(children: [ListTile(title: Text('Error: $e'))]),
              data: (students) => students.isEmpty
                  ? _InfoCard(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.person_off,
                            color: Theme.of(context).hintColor,
                          ),
                          title: const Text('No student profiles on this device'),
                        ),
                      ],
                    )
                  : _InfoCard(
                      children: students
                          .map((s) => _StudentRow(student: s))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 20),

            // ── Updates ──────────────────────────────────────────────────
            const _SectionTitle('Updates'),
            _InfoCard(
              children: [
                const _InfoRow(
                  icon: Icons.usb,
                  label: 'Update method',
                  value: 'USB drive or local school server — never internet',
                ),
                ListTile(
                  leading: Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('How to update', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '1. Receive the update package on a USB drive\n'
                    '2. Copy the new app installer to this device\n'
                    '3. Run the installer — student data is preserved\n'
                    '4. New model files go in the model folder',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Danger zone ──────────────────────────────────────────────
            const _SectionTitle('Reset'),
            pinSetAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (pinSet) => _InfoCard(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever,
                      color: pinSet ? Colors.red : Theme.of(context).hintColor,
                    ),
                    title: Text(
                      'Reset all student data',
                      style: TextStyle(
                        color: pinSet ? Colors.red : Theme.of(context).hintColor,
                      ),
                    ),
                    subtitle: Text(
                      pinSet
                          ? 'Deletes every learner profile, their progress, '
                              'badges, projects and chat sessions on this '
                              'device. Curriculum, teacher notes/subjects, '
                              'classes and installed models are untouched.'
                          : 'Set a Teacher PIN first (Settings → Teacher '
                              'PIN) — this stays locked until this device '
                              'requires one to reach Teacher/Admin at all.',
                    ),
                    enabled: pinSet,
                    onTap: pinSet ? () => _confirmResetAll(context, ref) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _confirmResetAll(BuildContext context, WidgetRef ref) {
    // Captured before the dialog's await, not merely before the wipe — the
    // callback below already runs past one async gap by the time it's
    // reached (the dialog itself), which is exactly what
    // use_build_context_synchronously is warning about.
    final router = GoRouter.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all student data?'),
        content: const Text(
          'This permanently deletes every learner profile on this device — '
          'progress, badges, projects, and chat sessions. Curriculum, '
          'teacher notes/subjects, classes and installed models stay. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      // router was captured before the dialog opened. Navigating off
      // /admin before the teacher-area lock changes below is defensive:
      // the router's redirect reads teacherUnlockedProvider on every
      // navigation and /admin is a gated route, so ordering it this way
      // means a lock-then-navigate race can't strand this screen on
      // /unlock even if something later makes that state trigger a
      // refresh — it doesn't appear to today.
      await ref.read(learnerDataWiperProvider).wipeAll();
      ref.invalidate(_allStudentsProvider);
      ref.invalidate(activeStudentProvider);
      ref.invalidate(hasProfileProvider);
      router.go('/onboarding');
      // Stronger than an ordinary learner switch (CLAUDE.md treats that as
      // its own privacy boundary): the learner this device was mid-session
      // as is now gone entirely, so its chat thread, tutor memory and the
      // engine's KV cache must not carry over to whoever onboards next —
      // and the device hands back to a learner, so the teacher area locks.
      ref.read(chatProvider.notifier).reset();
      ref.read(teacherUnlockedProvider.notifier).state = false;
    });
  }
}

/// All students on the device (admin view — not just the active one).
final _allStudentsProvider = FutureProvider<List<Student>>((ref) {
  final db = ref.watch(dbProvider);
  return db.studentDao.getAllStudents();
});

/// Whether a Teacher PIN exists — the reset tile stays locked without one,
/// since with no PIN set nothing gates `/admin` at all (see teacher_pin.dart)
/// and "teachers/admins only" would otherwise be nominal.
///
/// autoDispose, not a plain FutureProvider: a PIN set moments ago in
/// Settings must unlock this tile the next time Admin is opened, not only
/// after the app restarts and the cached `false` is gone.
final _pinSetProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(teacherPinProvider).isSet();
});

class _StudentRow extends ConsumerWidget {
  const _StudentRow({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same lock as "Reset all student data" below, and for the same
    // reason: with no PIN set nothing gates /admin at all (teacher_pin.dart),
    // so without this check any learner who opens Admin could delete
    // another learner's profile — exactly what "teachers/admins only" is
    // supposed to prevent.
    final pinSet = ref.watch(_pinSetProvider).valueOrNull ?? false;
    return ListTile(
      title: Text(student.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        '${student.totalPoints} pts · ${student.streakDays} day streak',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: pinSet ? Colors.red : Theme.of(context).hintColor,
          size: 20,
        ),
        tooltip: pinSet ? 'Delete profile' : 'Set a Teacher PIN first',
        onPressed: pinSet ? () => _confirmDelete(context, ref) : null,
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    // Captured before the dialog opens, both so it's safe to use afterward
    // (the .then callback below runs past that async gap) and, for the
    // wipeAll-equivalent branch inside it, so navigating off /admin can
    // happen before the teacher-area lock changes — see the matching note
    // in _confirmResetAll on why that order avoids a router redirect race.
    final router = GoRouter.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${student.name}?'),
        content: const Text(
          'This permanently removes the profile and all learning data '
          '(paths, badges, projects, sessions). This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      final wasActive =
          (await ref.read(activeStudentProvider.future))?.id == student.id;

      // Nothing in this app enables `PRAGMA foreign_keys`, so cascades
      // declared on these tables are never enforced — LearnerDataWiper is
      // the one place that clears every table actually scoped to a
      // student, so a deleted profile can't leave orphaned rows in a table
      // this dialog's old inline version predates (session_summaries,
      // topic_progress, learning_paths, earned_badges, student_projects,
      // website_projects, app_builder_projects, assignments were all
      // missed before).
      await ref.read(learnerDataWiperProvider).wipeStudent(student.id);

      // Read fresh, after the delete — _allStudentsProvider's cache still
      // holds the pre-delete list until invalidated below, and reading
      // that here would make a lone remaining learner look like there
      // were none, or a just-deleted one look like it were still there.
      final remaining = await ref.read(dbProvider).studentDao.getAllStudents();
      ref.invalidate(_allStudentsProvider);
      ref.invalidate(activeStudentProvider);
      ref.invalidate(hasProfileProvider);

      if (!wasActive) return;
      // Same privacy boundary a learner switch enforces (CLAUDE.md) — the
      // learner whose thread/tutor-memory/KV cache this device was holding
      // no longer exists, so none of it may reach whoever uses the device
      // next.
      ref.read(chatProvider.notifier).reset();
      if (remaining.isEmpty) {
        // Same situation wipeAll leaves the device in — the wiper already
        // cleared the router's `student_name` onboarding flag once this
        // was the last learner, so onboarding is the only correct landing.
        router.go('/onboarding');
        ref.read(teacherUnlockedProvider.notifier).state = false;
      } else {
        // resolveActiveStudent's fallback (most-recently-active) would
        // otherwise silently turn the device into some other learner
        // without going through LearnerSwitcher — no language change, no
        // explicit choice. Send the admin to pick, the same as any other
        // handoff.
        router.go('/learners');
      }
    });
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        value,
        style: TextStyle(fontSize: 12, color: valueColor ?? Theme.of(context).hintColor),
      ),
    );
  }
}
