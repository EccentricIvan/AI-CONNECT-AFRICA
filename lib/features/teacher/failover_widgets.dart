import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../collaboration/sync/class_share_server.dart';
import '../../collaboration/sync/failover_crypto.dart';
import '../../collaboration/sync/p2p_failover_service.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/studio_page.dart';

/// "18 Sep, 14:05" — short enough for a card line.
String failoverTime(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = t.toLocal();
  return '${l.day} ${months[l.month - 1]}, '
      '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// Asks for a new failover passphrase twice. Null when cancelled.
Future<String?> askNewPassphrase(BuildContext context) async {
  final first = TextEditingController(), second = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Failover passphrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                helperText: 'At least $kMinPassphraseLength characters',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: second,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm passphrase',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text != second.text) {
                setLocal(() => error = 'Passphrases don’t match');
                return;
              }
              Navigator.pop(ctx, first.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  first.dispose();
  second.dispose();
  return result;
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        showCloseIcon: true,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ),
    );
}

/// Teacher device: the standby that can take over if this device is lost.
///
/// Set the passphrase any time; pairing needs [server] (this device sharing
/// a class as teacher), because the standby pairs and backs up over it.
/// The standby's request shows in the `JoinRequestsCard` above for Accept.
class StandbyHostCard extends ConsumerStatefulWidget {
  const StandbyHostCard({
    super.key,
    required this.identity,
    required this.server,
  });

  final SyncIdentityData? identity;

  /// The running teacher server, or null while not sharing.
  final ClassShareServer? server;

  @override
  ConsumerState<StandbyHostCard> createState() => _StandbyHostCardState();
}

class _StandbyHostCardState extends ConsumerState<StandbyHostCard> {
  late final P2PFailoverService _service = P2PFailoverService(
    ref.read(dbProvider),
  );
  bool _busy = false;
  String? _code;
  DateTime? _codeExpires;

  @override
  void didUpdateWidget(StandbyHostCard old) {
    super.didUpdateWidget(old);
    // A code belongs to the server that opened it.
    if (old.server != widget.server) {
      _code = null;
      _codeExpires = null;
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  bool get _hasPassphrase => widget.identity?.failoverSealKey != null;
  bool get _serving => widget.server?.isRunning ?? false;

  Future<void> _setPassphrase() async {
    final pass = await askNewPassphrase(context);
    if (pass == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _service.enableFailover(pass);
      if (!mounted) return;
      _snack(
        context,
        r.ok
            ? 'Passphrase saved'
            : r.error!,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pair() async {
    final code = await widget.server?.openStandbyCode();
    if (!mounted) return;
    if (code == null) {
      _snack(context, 'Start sharing a class first');
      return;
    }
    setState(() {
      _code = code;
      _codeExpires = DateTime.now().add(kStandbyCodeTtl);
    });
  }

  Future<void> _remove(FailoverStandby s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${s.name}?'),
        content: const Text(
          'If the device was lost, also change the passphrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _service.removeStandby(s.publicKey);
  }

  /// The same sealed backup a standby pulls, onto a USB stick or SD card.
  Future<void> _exportFile() async {
    setState(() => _busy = true);
    try {
      final ledger = await _service.exportLedger();
      if (!mounted) return;
      if (ledger == null) {
        _snack(context, 'Set a passphrase first');
        return;
      }
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(ledger)));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save teacher-device backup',
        fileName: 'otic-teacher-backup.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (path == null) return;
      // On desktop saveFile only returns the chosen path; Android wrote it.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (mounted) {
        _snack(context, 'Backup saved');
      }
    } catch (e) {
      if (mounted) _snack(context, 'Couldn’t save the backup');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final small = TextStyle(fontSize: 12, color: ac.textSecondary);
    return StudioCard(
      accent: _hasPassphrase ? AppColors.accentGreen : AppColors.accentOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.backup_rounded, size: 20),
              const SizedBox(width: 8),
              Text(
                'Standby device',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ac.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || widget.identity?.schoolId == null
                    ? null
                    : _setPassphrase,
                icon: const Icon(Icons.key_rounded, size: 18),
                label: Text(
                  _hasPassphrase ? 'Change passphrase' : 'Set passphrase',
                ),
              ),
              if (_hasPassphrase)
                FilledButton.icon(
                  onPressed: _busy || !_serving ? null : _pair,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Pair device'),
                ),
              if (_hasPassphrase)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportFile,
                  icon: const Icon(Icons.usb_rounded, size: 18),
                  label: const Text('Export backup'),
                ),
            ],
          ),
          if (_hasPassphrase && !_serving)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Pairing is available while sharing', style: small),
            ),
          if (_code != null && _serving) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SelectableText(
                  _code!,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _code!)),
                ),
              ],
            ),
            Text(
              'Valid until ${failoverTime(_codeExpires!)}',
              style: small,
            ),
          ],
          StreamBuilder<List<FailoverStandby>>(
            stream: _service.watchStandbys(),
            builder: (context, snap) {
              final standbys = snap.data ?? const <FailoverStandby>[];
              if (standbys.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  for (final s in standbys)
                    Row(
                      children: [
                        const Icon(Icons.devices_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: TextStyle(color: ac.textPrimary),
                              ),
                              Text(
                                s.lastMirroredAt == null
                                    ? 'No backup yet'
                                    : 'Backed up ${failoverTime(s.lastMirroredAt!)}',
                                style: small,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _remove(s),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Link to the standby side — on the teacher's Class sync screen, including
/// a fresh replacement device with no classes yet.
class StandbyScreenLink extends StatelessWidget {
  const StandbyScreenLink({super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => context.push('/teacher/standby'),
    icon: const Icon(Icons.restore_rounded, size: 18),
    label: const Text('Standby device'),
  );
}
