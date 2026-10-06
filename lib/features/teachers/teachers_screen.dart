import 'dart:convert';
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
import '../teacher/class_providers.dart';
import '../teacher/co_teacher_widgets.dart';
import '../teacher/failover_widgets.dart';
import '../teacher/teacher_pin.dart';
import '../teacher/teacher_pin_screen.dart';
import '../teacher/teacher_profiles.dart';

/// Teachers — the school's teacher devices and everything that manages this
/// one: the teacher tools, the school, learner profiles, learning packages
/// and updates. Replaced the separate Admin dashboard: a school has several
/// teachers (co-teachers, a standby), and they are the ones who manage the
/// devices.
///
/// PIN-gated like the rest of the teacher area, but not role-gated: a
/// student's device has learners to manage too, so the teacher-device
/// sections only appear where they apply.
class TeachersScreen extends ConsumerWidget {
  const TeachersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelAsync = ref.watch(modelInfoProvider);
    final studentsAsync = ref.watch(_allStudentsProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);
    final pinSetAsync = ref.watch(_pinSetProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'Teachers'),
        subtitle: tr(context, 'Devices, learners and school'),
        icon: Icons.groups_rounded,
        iconColor: AppColors.accentBlue,
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Teachers ─────────────────────────────────────────────────
            const _SectionTitle('Teachers'),
            const _TeacherDevicesCard(),
            const SizedBox(height: 20),

            // ── School ───────────────────────────────────────────────────
            const _SectionTitle('School'),
            const _SchoolCard(),
            const SizedBox(height: 20),

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
                    data: (info) =>
                        'Version ${info.version} (build ${info.buildNumber})',
                    loading: () => 'Loading…',
                    error: (_, __) => 'Unknown',
                  ),
                ),
                const _InfoRow(
                  icon: Icons.wifi_off,
                  label: 'Network',
                  value: 'Offline',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── AI Model ─────────────────────────────────────────────────
            const _SectionTitle('Learning packages'),
            modelAsync.when(
              loading: () => const _InfoCard(
                children: [ListTile(title: Text('Checking packages…'))],
              ),
              error: (e, _) => _InfoCard(
                children: [ListTile(title: Text('Package check failed: $e'))],
              ),
              data: (info) => _InfoCard(
                children: [
                  _InfoRow(
                    icon: Icons.memory,
                    label: 'Classroom assistant',
                    value: info.isReady ? 'Installed' : 'Not installed',
                    valueColor: info.isReady
                        ? AppColors.teachColor
                        : Colors.orange,
                  ),
                  if (info.isReady && info.sizeBytes != null)
                    _InfoRow(
                      icon: Icons.sd_storage,
                      label: 'Package size',
                      value:
                          '${(info.sizeBytes! / (1024 * 1024)).toStringAsFixed(0)} MB',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Users ────────────────────────────────────────────────────
            const _SectionTitle('Learners on this device'),
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
                          title: const Text('No learners'),
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
                  value: 'USB or school server',
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
                        color: pinSet
                            ? Colors.red
                            : Theme.of(context).hintColor,
                      ),
                    ),
                    subtitle: pinSet ? null : const Text('Requires a PIN'),
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
          'All learner profiles and their progress will be deleted. This '
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
      // /teachers before the teacher-area lock changes below is defensive:
      // the router's redirect reads teacherUnlockedProvider on every
      // navigation and /teachers is a gated route, so ordering it this way
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
      ref.read(activeTeacherProvider.notifier).state = null;
    });
  }
}

/// All students on the device (not just the active one).
final _allStudentsProvider = FutureProvider<List<Student>>((ref) {
  final db = ref.watch(dbProvider);
  return db.studentDao.getAllStudents();
});

/// Whether a Teacher PIN exists — the reset tile stays locked without one,
/// since with no PIN set nothing gates `/teachers` at all (see teacher_pin.dart)
/// and "teachers/admins only" would otherwise be nominal.
///
/// autoDispose, not a plain FutureProvider: a PIN set moments ago in
/// Settings must unlock this tile the next time Teachers is opened, not only
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
    // reason: with no PIN set nothing gates /teachers at all (teacher_pin.dart),
    // so without this check any learner who opens Teachers could delete
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
        tooltip: pinSet ? 'Delete' : 'Requires a PIN',
        onPressed: pinSet ? () => _confirmDelete(context, ref) : null,
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    // Captured before the dialog opens, both so it's safe to use afterward
    // (the .then callback below runs past that async gap) and, for the
    // wipeAll-equivalent branch inside it, so navigating off /teachers can
    // happen before the teacher-area lock changes — see the matching note
    // in _confirmResetAll on why that order avoids a router redirect race.
    final router = GoRouter.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${student.name}?'),
        content: const Text('This cannot be undone.'),
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
        ref.read(activeTeacherProvider.notifier).state = null;
      } else {
        // resolveActiveStudent's fallback (most-recently-active) would
        // otherwise silently turn the device into some other learner
        // without going through LearnerSwitcher — no language change, no
        // explicit choice. Send the teacher to pick, the same as any other
        // handoff.
        router.go('/learners');
      }
    });
  }
}

/// The school this device belongs to. Class sync only ever shares notes
/// between devices of the same school, so a teacher's device needs one
/// before it can share; a student's device takes it from the first class it
/// joins.
class _SchoolCard extends ConsumerWidget {
  const _SchoolCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(syncIdentityProvider).valueOrNull;
    final name = identity?.schoolName;
    final hasSchool = identity?.schoolId != null && (name ?? '').isNotEmpty;
    return _InfoCard(
      children: [
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(hasSchool ? name! : 'No school set'),
          trailing: TextButton(
            onPressed: () => _edit(context, ref, name),
            child: Text(hasSchool ? 'Rename' : 'Set school'),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final controller = TextEditingController(text: current ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('School name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Bright Future Academy',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await ref.read(dbProvider).classSyncDao.setSchoolName(name);
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
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 12,
          color: valueColor ?? Theme.of(context).hintColor,
        ),
      ),
    );
  }
}

/// Every co-teacher of this device's own classes.
final _allCoTeachersProvider = StreamProvider.autoDispose<List<ClassCoTeacher>>(
  (ref) {
    final db = ref.watch(dbProvider);
    return db.select(db.classCoTeachers).watch();
  },
);

/// Standby devices paired with this teacher device (host failover).
final _standbysProvider = StreamProvider.autoDispose<List<FailoverStandby>>((
  ref,
) {
  final db = ref.watch(dbProvider);
  return db.select(db.failoverStandbys).watch();
});

/// The teachers who use this device. Signed out: their profiles to sign in
/// to, and adding one. Signed in: what that teacher teaches, the devices
/// their classes work with, and the teacher tools.
class _TeacherDevicesCard extends ConsumerWidget {
  const _TeacherDevicesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(activeTeacherProvider);
    final hint = Theme.of(context).hintColor;
    final chevron = Icon(Icons.chevron_right, color: hint);

    if (me == null) {
      final profiles =
          ref.watch(teacherProfilesProvider).valueOrNull ??
          const <TeacherProfile>[];
      return _InfoCard(
        children: [
          for (final t in profiles)
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(t.name),
              trailing: chevron,
              onTap: () => _signIn(context, ref, t),
            ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded),
            title: const Text('Add teacher'),
            trailing: chevron,
            onTap: () => _addTeacher(context, ref),
          ),
        ],
      );
    }

    final owned =
        ref.watch(ownedClassesProvider).valueOrNull ?? const <ClassGroup>[];
    final delegated =
        ref.watch(delegatedClassesProvider).valueOrNull ??
        const <CoTeachingClass>[];
    final standbys =
        ref.watch(_standbysProvider).valueOrNull ?? const <FailoverStandby>[];
    final names = subjectNames(ref);
    final classByUuid = {
      for (final c in owned)
        if (c.groupUuid != null) c.groupUuid!: c,
    };
    final coTeachers = [
      for (final t
          in ref.watch(_allCoTeachersProvider).valueOrNull ??
              const <ClassCoTeacher>[])
        if (classByUuid.containsKey(t.classGroupUuid)) t,
    ];
    List<String> subjectsOf(String json) {
      try {
        return [
          for (final s in jsonDecode(json) as List)
            if (s is String) names(s),
        ];
      } catch (_) {
        return const [];
      }
    }

    final mine = [
      if (owned.isNotEmpty)
        'teaches ${owned.length} ${owned.length == 1 ? 'class' : 'classes'}',
      if (delegated.isNotEmpty)
        'co-teaches ${delegated.length} '
            '${delegated.length == 1 ? 'class' : 'classes'}',
    ];

    return Column(
      children: [
        _InfoCard(
          children: [
            ListTile(
              leading: const Icon(Icons.verified_user_rounded),
              title: Text(me.name),
              subtitle: Text(mine.isEmpty ? 'No classes' : mine.join(' · ')),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(activeTeacherProvider.notifier).state = null,
                child: const Text('Sign out'),
              ),
            ),
            for (final t in coTeachers)
              ListTile(
                leading: const Icon(Icons.school_rounded),
                title: Text(t.name.isEmpty ? 'Co-teacher' : t.name),
                subtitle: Text(
                  'Co-teacher · '
                  '${classLabel(classByUuid[t.classGroupUuid]!)}'
                  '${subjectsOf(t.subjectIdsJson).isEmpty ? '' : ': ${subjectsOf(t.subjectIdsJson).join(', ')}'}',
                ),
              ),
            for (final d in delegated)
              ListTile(
                leading: const Icon(Icons.group_add_rounded),
                title: Text('${delegatedClassLabel(d)}’s teacher'),
                subtitle: Text(
                  subjectsOf(d.subjectIdsJson).isEmpty
                      ? 'Revoked'
                      : 'You co-teach: ${subjectsOf(d.subjectIdsJson).join(', ')}',
                ),
              ),
            for (final s in standbys)
              ListTile(
                leading: const Icon(Icons.backup_rounded),
                title: Text(s.name),
                subtitle: Text(
                  s.lastMirroredAt == null
                      ? 'Standby · no backup yet'
                      : 'Standby · backed up '
                            '${failoverTime(s.lastMirroredAt!)}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          children: [
            for (final (icon, title, path) in const [
              (Icons.groups_outlined, 'Classes & learners', '/teacher'),
              (
                Icons.folder_copy_outlined,
                'Lesson materials',
                '/teacher/materials',
              ),
              (Icons.sync_rounded, 'Class sync', '/teacher/sync'),
              (Icons.group_add_outlined, 'Co-teaching', '/teacher/co-teach'),
              (Icons.restore_rounded, 'Standby device', '/teacher/standby'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(title),
                trailing: chevron,
                onTap: () => context.push(path),
              ),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('My PIN'),
              trailing: chevron,
              onTap: () => _changeMyPin(context, ref, me),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Teachers PIN'),
              trailing: chevron,
              onTap: () => showTeacherPinSettings(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signIn(
    BuildContext context,
    WidgetRef ref,
    TeacherProfile teacher,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final pin = await askTeacherPin(context, title: teacher.name);
    if (pin == null) return;
    final signedIn = await ref
        .read(teacherProfileServiceProvider)
        .signIn(teacher.id, pin);
    if (signedIn == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That PIN is not right.')),
      );
      return;
    }
    ref.read(activeTeacherProvider.notifier).state = signedIn;
  }

  /// Adds a profile. With no Teachers PIN yet, it is set first: profiles
  /// sit behind the PIN every teacher knows, so a learner can't make one.
  Future<void> _addTeacher(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final teachersPin = ref.read(teacherPinProvider);
    if (!await teachersPin.isSet()) {
      if (!context.mounted) return;
      await showTeacherPinSettings(context, ref);
      if (!await teachersPin.isSet() || !context.mounted) return;
    }
    final name = TextEditingController();
    final pin = TextEditingController();
    final again = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add teacher'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: kPinInputFormatters,
                decoration: const InputDecoration(
                  labelText: 'PIN (4–8 digits)',
                ),
              ),
              TextField(
                controller: again,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: kPinInputFormatters,
                decoration: const InputDecoration(labelText: 'PIN again'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final (n, p, a) = (name.text, pin.text.trim(), again.text.trim());
    name.dispose();
    pin.dispose();
    again.dispose();
    if (ok != true) return;
    if (p != a) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The two PINs did not match.')),
      );
      return;
    }
    final r = await ref
        .read(teacherProfileServiceProvider)
        .create(name: n, pin: p);
    if (r.profile == null) {
      messenger.showSnackBar(SnackBar(content: Text(r.error ?? '')));
      return;
    }
    ref.read(activeTeacherProvider.notifier).state = r.profile;
  }

  Future<void> _changeMyPin(
    BuildContext context,
    WidgetRef ref,
    TeacherProfile me,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = await askTeacherPin(context, title: 'Current PIN');
    if (current == null || !context.mounted) return;
    final next = await askTeacherPin(context, title: 'New PIN (4–8 digits)');
    if (next == null || !context.mounted) return;
    final again = await askTeacherPin(context, title: 'New PIN again');
    if (again == null) return;
    if (again != next) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The two PINs did not match.')),
      );
      return;
    }
    final changed = await ref
        .read(teacherProfileServiceProvider)
        .changePin(me.id, current, next);
    messenger.showSnackBar(
      SnackBar(
        content: Text(changed ? 'PIN changed.' : 'That PIN is not right.'),
      ),
    );
  }
}
