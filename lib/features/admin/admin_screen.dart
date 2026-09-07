import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/app_info_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

/// Admin dashboard — device, user, and update management.
/// Admins manage the platform; they have no learning features here.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelAsync = ref.watch(modelInfoProvider);
    final studentsAsync = ref.watch(_allStudentsProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'Admin dashboard'),
        subtitle: tr(context, 'Device & learner management'),
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
                    label: 'Qwen3-0.6B (chat)',
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
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// All students on the device (admin view — not just the active one).
final _allStudentsProvider = FutureProvider<List<Student>>((ref) {
  final db = ref.watch(dbProvider);
  return db.studentDao.getAllStudents();
});

class _StudentRow extends ConsumerWidget {
  const _StudentRow({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(student.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        '${student.totalPoints} pts · ${student.streakDays} day streak',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
        tooltip: 'Delete profile',
        onPressed: () => _confirmDelete(context, ref),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
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
      final db = ref.read(dbProvider);
      await db.studentDao.deleteStudent(student.id);
      ref.invalidate(_allStudentsProvider);
      ref.invalidate(activeStudentProvider);
      ref.invalidate(hasProfileProvider);
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
