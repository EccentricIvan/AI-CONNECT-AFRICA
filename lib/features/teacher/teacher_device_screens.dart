import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

/// Shown the first time anyone opens the teacher section on a device that
/// is neither a teacher's nor a student's yet. A teacher's device creates
/// classes and subjects, students' devices join it, and their progress
/// arrives there; other teachers' devices can co-teach its classes' subjects.
class TeacherDeviceSetupScreen extends ConsumerStatefulWidget {
  const TeacherDeviceSetupScreen({super.key, required this.destination});

  final String destination;

  @override
  ConsumerState<TeacherDeviceSetupScreen> createState() =>
      _TeacherDeviceSetupScreenState();
}

class _TeacherDeviceSetupScreenState
    extends ConsumerState<TeacherDeviceSetupScreen> {
  bool _busy = false;

  Future<void> _claim() async {
    setState(() => _busy = true);
    final ok = await ref.read(dbProvider).classSyncDao.claimTeacherRole();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      context.go('/student-device');
      return;
    }
    // Whoever set the device up is the teacher; with a PIN already set they
    // still pass the PIN screen next.
    context.go(widget.destination);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Teacher device',
        subtitle: 'Device setup',
        icon: Icons.school_rounded,
        iconColor: AppColors.accentBlue,
        showBack: true,
      ),
      body: MaxWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            StudioCard(
              accent: AppColors.accentBlue,
              child: Text(
                'Is this a teacher device?',
                style: TextStyle(
                  color: ac.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _claim,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Yes, teacher device'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => context.go('/class-sync'),
              child: const Text('No, student device'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The teacher section on a student's device: it isn't here.
class StudentDeviceScreen extends StatelessWidget {
  const StudentDeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Student device',
        subtitle: 'Teacher tools are on the teacher device',
        icon: Icons.person_rounded,
        iconColor: AppColors.accentTeal,
        showBack: true,
      ),
      body: MaxWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            StudioCard(
              accent: AppColors.accentTeal,
              child: Text(
                'This device is registered to a class as a student device.',
                style: TextStyle(color: ac.textPrimary, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/class-sync'),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Open Class sync'),
            ),
          ],
        ),
      ),
    );
  }
}
