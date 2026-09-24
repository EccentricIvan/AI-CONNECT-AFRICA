import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import 'teacher_pin.dart';

/// Asks for the teacher PIN, then continues to [destination].
class TeacherUnlockScreen extends ConsumerStatefulWidget {
  const TeacherUnlockScreen({super.key, required this.destination});

  final String destination;

  @override
  ConsumerState<TeacherUnlockScreen> createState() =>
      _TeacherUnlockScreenState();
}

class _TeacherUnlockScreenState extends ConsumerState<TeacherUnlockScreen> {
  static const _maxAttempts = 5;
  static const _cooldown = Duration(seconds: 30);

  final _pin = TextEditingController();
  int _failures = 0;
  DateTime? _lockedUntil;
  String? _error;
  Timer? _tick;

  @override
  void dispose() {
    _pin.dispose();
    _tick?.cancel();
    super.dispose();
  }

  bool get _coolingDown =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  Future<void> _submit() async {
    if (_coolingDown) return;
    final ok = await ref.read(teacherPinProvider).verify(_pin.text.trim());
    if (!mounted) return;
    if (ok) {
      ref.read(teacherUnlockedProvider.notifier).state = true;
      context.go(widget.destination);
      return;
    }
    _pin.clear();
    _failures++;
    if (_failures >= _maxAttempts) {
      // Slows guessing down; a 4-digit PIN has only 10,000 values.
      _failures = 0;
      _lockedUntil = DateTime.now().add(_cooldown);
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!_coolingDown) t.cancel();
        if (mounted) setState(() {});
      });
    }
    setState(() => _error = 'That PIN is not right.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final wait = _coolingDown
        ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1
        : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Teacher area',
        subtitle: 'Enter the teacher PIN to continue',
        icon: Icons.lock_rounded,
        iconColor: AppColors.accentBlue,
        showBack: true,
      ),
      body: MaxWidth(
        maxWidth: 420,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              enabled: !_coolingDown,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                labelText: 'PIN',
                errorText: _coolingDown
                    ? 'Too many tries. Wait $wait s.'
                    : _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _coolingDown ? null : _submit,
              child: const Text('Unlock'),
            ),
            const SizedBox(height: 24),
            Text(
              'Forgot the PIN? It can only be removed by clearing this '
              "app's data, which also removes every learner's progress on "
              'this device.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings entry point: set a PIN, or change/remove the current one.
///
/// Changing or removing requires the current PIN, so a learner cannot simply
/// switch the lock off from Settings.
Future<void> showTeacherPinSettings(BuildContext context, WidgetRef ref) async {
  final pin = ref.read(teacherPinProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (await pin.isSet()) {
    if (!context.mounted) return;
    final current = await _askPin(context, title: 'Current teacher PIN');
    if (current == null) return;
    if (!await pin.verify(current)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That PIN is not right.')),
      );
      return;
    }
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Teacher PIN'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'change'),
            child: const Text('Change PIN'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text('Remove PIN'),
          ),
        ],
      ),
    );
    if (action == 'remove') {
      await pin.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Teacher PIN removed.')),
      );
      return;
    }
    if (action != 'change') return;
  }

  if (!context.mounted) return;
  final next = await _askPin(context, title: 'New teacher PIN (4–8 digits)');
  if (next == null) return;
  if (!TeacherPin.isValidFormat(next)) {
    messenger.showSnackBar(
      const SnackBar(content: Text('A PIN is 4 to 8 digits.')),
    );
    return;
  }
  if (!context.mounted) return;
  final again = await _askPin(context, title: 'Type the new PIN again');
  if (again == null) return;
  if (again != next) {
    messenger.showSnackBar(
      const SnackBar(content: Text('The two PINs did not match.')),
    );
    return;
  }
  await pin.set(next);
  // Whoever just set it is the teacher; don't lock them out mid-session.
  ref.read(teacherUnlockedProvider.notifier).state = true;
  messenger.showSnackBar(
    const SnackBar(content: Text('Teacher PIN set.')),
  );
}

Future<String?> _askPin(BuildContext context, {required String title}) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(8),
        ],
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value?.trim();
}
