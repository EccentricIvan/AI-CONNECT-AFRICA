import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../collaboration/sync/device_registry.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../services/custom_subject_service.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../learners/learner_pin.dart';
import '../teacher/class_providers.dart';
import '../teacher/teacher_pin.dart';
import '../teacher/teacher_pin_screen.dart';
import '../teacher/teacher_profiles.dart';
import 'admin_service.dart';
import 'admin_sync_widgets.dart';

/// The school's one Admin: set up once, then sign in with the Admin PIN.
/// Here the Admin keeps the school's records — teachers, classes and
/// streams, subjects, teaching assignments, learners and enrolments.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final setUp = ref.watch(adminSetUpProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Admin',
        subtitle: 'School records',
        icon: Icons.admin_panel_settings_rounded,
        iconColor: AppColors.accentBlue,
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: switch ((setUp, session)) {
          (null, _) => const Center(child: CircularProgressIndicator()),
          (false, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const ReceiveRecordsCard(),
              // One Admin per school: a device holding the school's records
              // is never set up as a second one.
              if (ref.watch(adminRecordsStateProvider).valueOrNull == null &&
                  !ref.watch(adminRecordsStateProvider).isLoading)
                const _SetUp(),
            ],
          ),
          (true, null) => const _SignIn(),
          (true, final s?) => _Records(session: s),
        },
      ),
    );
  }
}

// ── Set up / sign in ──────────────────────────────────────────────────────

class _SetUp extends ConsumerStatefulWidget {
  const _SetUp();

  @override
  ConsumerState<_SetUp> createState() => _SetUpState();
}

class _SetUpState extends ConsumerState<_SetUp> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pin.text != _again.text) {
      return setState(() => _error = 'The two PINs did not match.');
    }
    // With a Teachers PIN set, only someone who knows it sets up the Admin.
    final teachersPin = ref.read(teacherPinProvider);
    if (await teachersPin.isSet()) {
      if (!mounted) return;
      final pin = await askTeacherPin(context, title: 'Teachers PIN');
      if (pin == null || !await teachersPin.verify(pin)) {
        return setState(() => _error = 'That PIN is not right.');
      }
    }
    final session = await ref
        .read(adminServiceProvider)
        .setUp(name: _name.text, pin: _pin.text.trim());
    if (!mounted) return;
    if (session == null) {
      return setState(() => _error = 'Enter a name and a 4–8 digit PIN.');
    }
    ref.invalidate(adminSetUpProvider);
    ref.read(adminSessionProvider.notifier).state = session;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('Or set up the Admin', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: kPinInputFormatters,
          decoration: const InputDecoration(labelText: 'PIN (4–8 digits)'),
        ),
        TextField(
          controller: _again,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: kPinInputFormatters,
          decoration: InputDecoration(labelText: 'PIN again', errorText: _error),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _submit, child: const Text('Set up')),
      ],
    );
  }
}

class _SignIn extends ConsumerStatefulWidget {
  const _SignIn();

  @override
  ConsumerState<_SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<_SignIn> {
  final _pin = TextEditingController();
  String? _error;
  int _failures = 0;
  DateTime? _lockedUntil;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      return setState(() => _error = 'Too many tries. Wait a moment.');
    }
    final session = await ref.read(adminServiceProvider).signIn(_pin.text);
    if (!mounted) return;
    _pin.clear();
    if (session == null) {
      // Slows guessing down; a 4-digit PIN has only 10,000 values.
      if (++_failures >= 5) {
        _failures = 0;
        _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
      }
      return setState(() => _error = 'That PIN is not right.');
    }
    ref.read(adminSessionProvider.notifier).state = session;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: kPinInputFormatters,
          decoration: InputDecoration(labelText: 'Admin PIN', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _submit, child: const Text('Sign in')),
      ],
    );
  }
}

// ── The records ───────────────────────────────────────────────────────────

final _assignmentsProvider = StreamProvider<List<TeachingAssignment>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.teachingAssignments).watch();
});

final _enrolmentsProvider = StreamProvider<List<StudentEnrolment>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.studentEnrolments).watch();
});

/// This device's own subjects (never ones received from a class).
final _subjectsProvider = StreamProvider<List<CustomSubject>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.customSubjects)
        ..where((t) => t.classGroupUuid.isNull()))
      .watch();
});

/// Classes made on this device (never ones joined as a student).
final _classesProvider = StreamProvider<List<ClassGroup>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.classGroups)..where((t) => t.joined.equals(false)))
      .watch();
});

class _Records extends ConsumerWidget {
  const _Records({required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.read(adminServiceProvider);
    final teachers =
        ref.watch(teacherProfilesProvider).valueOrNull ??
        const <TeacherProfile>[];
    final classes =
        ref.watch(_classesProvider).valueOrNull ?? const <ClassGroup>[];
    final subjects =
        ref.watch(_subjectsProvider).valueOrNull ?? const <CustomSubject>[];
    final assignments =
        ref.watch(_assignmentsProvider).valueOrNull ??
        const <TeachingAssignment>[];
    final enrolments =
        ref.watch(_enrolmentsProvider).valueOrNull ??
        const <StudentEnrolment>[];
    final learners =
        ref.watch(allLearnersProvider).valueOrNull ?? const <Student>[];

    final teacherName = {for (final t in teachers) t.id: t.name};
    final classByUuid = {
      for (final c in classes)
        if (c.groupUuid != null) c.groupUuid!: c,
    };
    final subjectName = {for (final s in subjects) s.subjectId: s.name};
    String classOf(String uuid) =>
        classByUuid[uuid] == null ? '—' : classLabel(classByUuid[uuid]!);
    final activeClass = {
      for (final e in enrolments)
        if (e.status == 'active') e.studentId: e.classGroupUuid,
    };

    Future<void> run(Future<void> Function() f, [String? done]) async {
      final messenger = ScaffoldMessenger.of(context);
      await f();
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Admin ──────────────────────────────────────────────────────
        _Card(
          children: [
            ListTile(
              leading: const Icon(Icons.verified_user_rounded),
              title: Text(session.name),
              subtitle: const Text('Admin'),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(adminSessionProvider.notifier).state = null,
                child: const Text('Sign out'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('My PIN'),
              onTap: () => _changeMyPin(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Send school records'),
              subtitle: const Text('To another device, one way'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SendRecordsPage()),
              ),
            ),
          ],
        ),

        // ── School ─────────────────────────────────────────────────────
        const _Title('School'),
        const _SchoolCard(),

        // ── Teachers ───────────────────────────────────────────────────
        _Title(
          'Teachers',
          onAdd: () => _addTeacher(context, ref),
        ),
        _Card(
          children: [
            if (teachers.isEmpty) const ListTile(title: Text('No teachers')),
            for (final t in teachers)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(t.name),
                subtitle: Text(
                  '${assignments.where((a) => a.teacherId == t.id).length} '
                  'assignments',
                ),
                trailing: _Menu({
                  'Reset PIN': () async {
                    final pin = await askTeacherPin(
                      context,
                      title: 'New PIN for ${t.name}',
                    );
                    if (pin == null) return;
                    await run(
                      () => admin.resetTeacherPin(session, t.id, pin),
                      'PIN reset.',
                    );
                  },
                  'Remove': () async {
                    if (await _confirm(context, 'Remove ${t.name}?')) {
                      await run(() => admin.removeTeacher(session, t.id));
                    }
                  },
                }),
              ),
          ],
        ),

        // ── Classes and streams ────────────────────────────────────────
        _Title(
          'Classes & streams',
          onAdd: () => _editClass(context, ref),
        ),
        _Card(
          children: [
            if (classes.isEmpty) const ListTile(title: Text('No classes')),
            for (final c in classes)
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: Text(classLabel(c)),
                subtitle: Text(
                  '${activeClass.values.where((u) => u == c.groupUuid).length} '
                  'learners',
                ),
                trailing: _Menu({
                  'Rename': () => _editClass(context, ref, existing: c),
                  'Delete': () async {
                    if (await _confirm(
                      context,
                      'Delete ${classLabel(c)}? Learners stay.',
                    )) {
                      await run(() => admin.deleteClass(session, c));
                    }
                  },
                }),
              ),
          ],
        ),

        // ── Subjects ───────────────────────────────────────────────────
        _Title('Subjects', onAdd: () => _addSubject(context, ref)),
        _Card(
          children: [
            if (subjects.isEmpty) const ListTile(title: Text('No subjects')),
            for (final s in subjects)
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: Text(s.name),
                trailing: _Menu({
                  'Rename': () async {
                    final name = await _ask(context, 'Subject', s.name);
                    if (name == null) return;
                    await run(() => admin.renameSubject(session, s.subjectId, name));
                    ref.invalidate(customSubjectsProvider);
                    ref.invalidate(mergedSubjectsProvider);
                  },
                  'Delete': () async {
                    if (await _confirm(
                      context,
                      'Delete ${s.name} and all its materials?',
                    )) {
                      await run(() => admin.deleteSubject(session, s.subjectId));
                      ref.invalidate(customSubjectsProvider);
                      ref.invalidate(mergedSubjectsProvider);
                    }
                  },
                }),
              ),
          ],
        ),

        // ── Teaching assignments ───────────────────────────────────────
        _Title(
          'Teaching assignments',
          onAdd: teachers.isEmpty || classes.isEmpty || subjects.isEmpty
              ? null
              : () => _assign(context, ref, teachers, classes, subjects),
        ),
        _Card(
          children: [
            if (assignments.isEmpty)
              const ListTile(title: Text('No assignments')),
            for (final a in assignments)
              ListTile(
                leading: const Icon(Icons.assignment_ind_rounded),
                title: Text(
                  '${teacherName[a.teacherId] ?? '—'} · '
                  '${subjectName[a.subjectId] ?? a.subjectId}',
                ),
                subtitle: Text(
                  '${classOf(a.classGroupUuid)} · ${a.academicYear}'
                  '${a.term == 0 ? '' : ' · Term ${a.term}'}',
                ),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => run(() => admin.unassign(session, a.id)),
                ),
              ),
          ],
        ),

        // ── Learners ───────────────────────────────────────────────────
        _Title('Learners', onAdd: () => _addLearner(context, ref)),
        _Card(
          children: [
            if (learners.isEmpty) const ListTile(title: Text('No learners')),
            for (final l in learners)
              ListTile(
                leading: const Icon(Icons.school_rounded),
                title: Text(l.name),
                subtitle: Text(
                  activeClass[l.id] == null
                      ? 'Not enrolled'
                      : classOf(activeClass[l.id]!),
                ),
                trailing: _Menu({
                  if (classes.isNotEmpty)
                    'Enrol': () async {
                      final c = await _pick<ClassGroup>(
                        context,
                        'Enrol ${l.name} in',
                        {for (final c in classes) classLabel(c): c},
                      );
                      if (c == null) return;
                      await run(
                        () => admin.enrol(
                          session,
                          studentId: l.id,
                          group: c,
                          academicYear: DateTime.now().year,
                        ),
                      );
                      ref.invalidate(activeStudentProvider);
                    },
                  if (activeClass[l.id] != null)
                    'Withdraw': () => run(() => admin.withdraw(session, l.id)),
                  if (l.pinHash != null)
                    'Clear PIN': () => run(
                      () => ref.read(learnerPinServiceProvider).clear(l.id),
                      'PIN cleared.',
                    ),
                  'Delete': () => _deleteLearner(context, ref, l),
                }),
              ),
          ],
        ),

        // ── Devices ────────────────────────────────────────────────────
        const _Title('Devices'),
        _DevicesCard(session: session),

        // ── Reset ──────────────────────────────────────────────────────
        const _Title('Reset'),
        _Card(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'Reset all learner data',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => _resetAll(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Future<void> _changeMyPin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = await askTeacherPin(context, title: 'Current PIN');
    if (current == null || !context.mounted) return;
    final next = await askTeacherPin(context, title: 'New PIN (4–8 digits)');
    if (next == null || !context.mounted) return;
    final again = await askTeacherPin(context, title: 'New PIN again');
    if (again == null) return;
    final ok =
        again == next &&
        await ref.read(adminServiceProvider).changePin(session, current, next);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? 'PIN changed.' : 'PIN not changed.')),
    );
  }

  Future<void> _addTeacher(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _ask(context, 'Teacher’s name', '');
    if (name == null || !context.mounted) return;
    final pin = await askTeacherPin(context, title: 'PIN for $name (4–8 digits)');
    if (pin == null) return;
    final error = await ref
        .read(adminServiceProvider)
        .addTeacher(session, name: name, pin: pin);
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Teacher added.')));
  }

  Future<void> _editClass(
    BuildContext context,
    WidgetRef ref, {
    ClassGroup? existing,
  }) async {
    final name = TextEditingController(text: existing?.className ?? '');
    final stream = TextEditingController(text: existing?.streamName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New class' : 'Rename class'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  hintText: 'e.g. S2',
                ),
              ),
              TextField(
                controller: stream,
                decoration: const InputDecoration(
                  labelText: 'Stream (optional)',
                  hintText: 'e.g. East',
                ),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final (c, s) = (name.text.trim(), stream.text.trim());
    name.dispose();
    stream.dispose();
    if (ok != true || c.isEmpty) return;
    final admin = ref.read(adminServiceProvider);
    if (existing == null) {
      await admin.addClass(session, className: c, streamName: s);
    } else {
      await admin.renameClass(session, existing.id, className: c, streamName: s);
    }
  }

  Future<void> _addSubject(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _ask(context, 'Subject', '');
    if (name == null) return;
    final r = await ref.read(adminServiceProvider).addSubject(session, name);
    ref.invalidate(customSubjectsProvider);
    ref.invalidate(mergedSubjectsProvider);
    if (!r.ok) messenger.showSnackBar(SnackBar(content: Text(r.error ?? '')));
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    List<TeacherProfile> teachers,
    List<ClassGroup> classes,
    List<CustomSubject> subjects,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final teacher = await _pick<TeacherProfile>(context, 'Teacher', {
      for (final t in teachers) t.name: t,
    });
    if (teacher == null || !context.mounted) return;
    final group = await _pick<ClassGroup>(context, 'Class / stream', {
      for (final c in classes) classLabel(c): c,
    });
    if (group == null || !context.mounted) return;
    final subject = await _pick<CustomSubject>(context, 'Subject', {
      for (final s in subjects) s.name: s,
    });
    if (subject == null || !context.mounted) return;
    final term = await _pick<int>(context, 'Term', {
      'Whole year': 0,
      'Term 1': 1,
      'Term 2': 2,
      'Term 3': 3,
    });
    if (term == null || group.groupUuid == null) return;
    final added = await ref
        .read(adminServiceProvider)
        .assign(
          session,
          teacherId: teacher.id,
          classGroupUuid: group.groupUuid!,
          subjectId: subject.subjectId,
          academicYear: DateTime.now().year,
          term: term,
        );
    if (!added) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Already assigned.')),
      );
    }
  }

  Future<void> _addLearner(BuildContext context, WidgetRef ref) async {
    final name = await _ask(context, 'Learner’s name', '');
    if (name == null) return;
    await ref.read(adminServiceProvider).addLearner(session, name: name);
    ref.invalidate(allLearnersProvider);
  }

  Future<void> _deleteLearner(
    BuildContext context,
    WidgetRef ref,
    Student learner,
  ) async {
    final router = GoRouter.of(context);
    if (!await _confirm(context, 'Delete ${learner.name}? This cannot be undone.')) {
      return;
    }
    final wasActive =
        (await ref.read(activeStudentProvider.future))?.id == learner.id;
    await ref.read(adminServiceProvider).deleteLearner(session, learner.id);
    final remaining = await ref.read(dbProvider).studentDao.getAllStudents();
    ref.invalidate(activeStudentProvider);
    ref.invalidate(hasProfileProvider);
    if (!wasActive) return;
    // The learner this device was holding no longer exists: none of their
    // chat, tutor memory or engine session may reach the next person.
    ref.read(chatProvider.notifier).reset();
    if (remaining.isEmpty) {
      router.go('/onboarding');
      _lockAll(ref);
    } else {
      router.go('/learners');
    }
  }

  Future<void> _resetAll(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    if (!await _confirm(
      context,
      'Delete every learner and their progress? This cannot be undone.',
    )) {
      return;
    }
    await ref.read(adminServiceProvider).resetAllLearners(session);
    ref.invalidate(activeStudentProvider);
    ref.invalidate(hasProfileProvider);
    router.go('/onboarding');
    ref.read(chatProvider.notifier).reset();
    _lockAll(ref);
  }

  /// The device goes back to a learner: every teacher and Admin area locks.
  static void _lockAll(WidgetRef ref) {
    ref.read(teacherUnlockedProvider.notifier).state = false;
    ref.read(activeTeacherProvider.notifier).state = null;
    ref.read(adminSessionProvider.notifier).state = null;
  }
}

/// The school this device belongs to. Sync only ever shares between
/// devices of the same school.
class _SchoolCard extends ConsumerWidget {
  const _SchoolCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(syncIdentityProvider).valueOrNull;
    final name = identity?.schoolName;
    final hasSchool = identity?.schoolId != null && (name ?? '').isNotEmpty;
    return _Card(
      children: [
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(hasSchool ? name! : 'No school set'),
          trailing: TextButton(
            onPressed: () async {
              final next = await _ask(context, 'School name', name ?? '');
              if (next == null) return;
              await ref.read(dbProvider).classSyncDao.setSchoolName(next);
            },
            child: Text(hasSchool ? 'Rename' : 'Set school'),
          ),
        ),
      ],
    );
  }
}

/// Devices that took the school's records, with Revoke for the whole
/// school; revoked ones stay listed.
class _DevicesCard extends ConsumerWidget {
  const _DevicesCard({required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices =
        ref.watch(_schoolDevicesProvider).valueOrNull ?? const <SchoolDevice>[];
    final revoked = {
      for (final r
          in ref.watch(_revokedDevicesProvider).valueOrNull ??
              const <RevokedDevice>[])
        r.deviceKey,
    };
    return _Card(
      children: [
        if (devices.isEmpty) const ListTile(title: Text('No devices')),
        for (final d in devices)
          ListTile(
            leading: Icon(
              revoked.contains(d.deviceKey)
                  ? Icons.block_rounded
                  : Icons.devices_rounded,
            ),
            title: Text(d.name.isEmpty ? 'Device' : d.name),
            subtitle: Text(
              revoked.contains(d.deviceKey) ? 'Revoked' : 'Has the records',
            ),
            trailing: revoked.contains(d.deviceKey)
                ? null
                : TextButton(
                    onPressed: () async {
                      if (!await _confirm(
                        context,
                        'Revoke ${d.name.isEmpty ? 'this device' : d.name} '
                        'for the whole school?',
                      )) {
                        return;
                      }
                      await ref
                          .read(adminServiceProvider)
                          .revokeDevice(session, d.deviceKey, name: d.name);
                    },
                    child: const Text('Revoke'),
                  ),
          ),
        if (revoked.isNotEmpty)
          ListTile(
            dense: true,
            title: Text(
              'Reaches other devices with the next records you send',
              style: TextStyle(color: AppColors.of(context).textSecondary),
            ),
          ),
      ],
    );
  }
}

final _schoolDevicesProvider = StreamProvider.autoDispose<List<SchoolDevice>>(
  (ref) => DeviceRegistry(ref.watch(dbProvider)).watchSchoolDevices(),
);

final _revokedDevicesProvider = StreamProvider.autoDispose<List<RevokedDevice>>(
  (ref) => DeviceRegistry(ref.watch(dbProvider)).watchRevoked(),
);

// ── Small pieces ──────────────────────────────────────────────────────────

class _Title extends StatelessWidget {
  const _Title(this.text, {this.onAdd});
  final String text;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (onAdd != null)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Card(margin: EdgeInsets.zero, child: Column(children: children));
}

/// A row's actions, by label.
class _Menu extends StatelessWidget {
  const _Menu(this.actions);
  final Map<String, Future<void> Function()> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (label) => actions[label]?.call(),
      itemBuilder: (_) => [
        for (final label in actions.keys)
          PopupMenuItem(value: label, child: Text(label)),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> _ask(BuildContext context, String label, String initial) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
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
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<T?> _pick<T>(
  BuildContext context,
  String title,
  Map<String, T> options,
) => showDialog<T>(
  context: context,
  builder: (ctx) => SimpleDialog(
    title: Text(title),
    children: [
      for (final e in options.entries)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, e.value),
          child: Text(e.key),
        ),
    ],
  ),
);
