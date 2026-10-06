import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../collaboration/lan_discovery.dart';
import '../../collaboration/sync/class_crypto.dart';
import '../../collaboration/sync/mdns_discovery.dart';
import '../../collaboration/sync/p2p_failover_service.dart';
import '../../collaboration/sync/selective_sync_manager.dart';
import '../../collaboration/sync/sync_address.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import 'failover_widgets.dart';
import 'teacher_profiles.dart';

/// The standby side of host failover: pair this device as the teacher
/// device's standby, keep its backup fresh, and — if the teacher device is
/// gone — take over as the school's teacher device with the passphrase.
///
/// A replacement device that was never paired can take over too, from a
/// backup file saved on the teacher device (Class sync → Save backup).
class StandbyScreen extends ConsumerStatefulWidget {
  const StandbyScreen({super.key});

  @override
  ConsumerState<StandbyScreen> createState() => _StandbyScreenState();
}

class _StandbyScreenState extends ConsumerState<StandbyScreen> {
  late final P2PFailoverService _service = P2PFailoverService(
    ref.read(dbProvider),
  );
  LanDiscoveryService? _discovery;
  final MdnsSyncDiscovery _mdns = MdnsSyncDiscovery();
  List<LanPeer> _peers = const [];
  List<MdnsSyncPeer> _mdnsPeers = const [];
  String? _schoolTag;
  StreamSubscription<HostLedger?>? _ledgerSub;
  HostLedger? _ledger;
  bool _loaded = false;

  final _code = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;
  String? _lastPullError;

  @override
  void initState() {
    super.initState();
    final db = ref.read(dbProvider);
    _ledgerSub = (db.select(db.hostLedgers)..where((t) => t.id.equals(1)))
        .watchSingleOrNull()
        .listen(_onLedger);
    unawaited(_startDiscovery());
  }

  @override
  void dispose() {
    _ledgerSub?.cancel();
    _service
      ..stopMirroring()
      ..dispose();
    _code.dispose();
    _name.dispose();
    _address.dispose();
    _discovery?.dispose();
    unawaited(_mdns.dispose());
    super.dispose();
  }

  void _onLedger(HostLedger? ledger) {
    if (!mounted) return;
    final wasPaired = _ledger != null;
    setState(() {
      _ledger = ledger;
      _loaded = true;
      _schoolTag = ledger == null ? null : schoolTag(ledger.schoolId);
    });
    // Mirror only while this screen is open and this device is a standby.
    if (ledger != null && !wasPaired) {
      _service.startMirroring(() => _endpoints);
    } else if (ledger == null && wasPaired) {
      _service.stopMirroring();
    }
  }

  Future<void> _startDiscovery() async {
    if (kIsWeb) return;
    final service = LanDiscoveryService(displayName: 'Teacher', role: 'teacher');
    unawaited(_mdns.startDiscovering());
    _mdns.peers.listen((list) {
      if (mounted) setState(() => _mdnsPeers = list);
    });
    try {
      await service.start();
      service.peers.listen((list) {
        if (mounted) setState(() => _peers = list);
      });
      if (mounted) {
        setState(() => _discovery = service);
      } else {
        service.dispose();
      }
    } on SocketException {
      service.dispose();
    }
  }

  /// Teacher devices seen on the network (only the paired school's, once
  /// paired), then the typed address.
  List<TeacherEndpoint> get _endpoints {
    final found = <TeacherEndpoint>[];
    final seen = <String>{};
    void add(TeacherEndpoint e) {
      if (seen.add('${e.address}:${e.port}')) found.add(e);
    }

    for (final p in _peers) {
      final visible = _schoolTag == null
          ? p.isSyncServer
          : p.isSyncServer && p.schoolTag == _schoolTag;
      if (visible) add((address: p.address, port: p.syncPort!));
    }
    for (final m in _mdnsPeers) {
      add((address: m.address, port: m.port));
    }
    final typed = parseTeacherAddress(_address.text);
    if (typed != null) add(typed);
    return found;
  }

  void _message(String text) {
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

  Future<void> _pair() async {
    if (_busy || _code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await _service.pairAsStandby(
        hosts: _endpoints,
        typedCode: _code.text,
        name: _name.text.trim(),
      );
      if (!mounted) return;
      _message(
        r.ok
            ? 'Paired'
            : r.error!,
      );
      if (r.ok) _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUpNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _service.pullLedger(_endpoints);
      if (!mounted) return;
      setState(() => _lastPullError = r.error);
      _message(r.ok ? 'Backup up to date' : r.error!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopStandingBy() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text('Its backup will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(dbProvider);
    await db.delete(db.hostLedgers).go();
  }

  /// Passphrase + a typed confirmation. Null when cancelled.
  Future<String?> _askTakeOver(String schoolName) async {
    final pass = TextEditingController(), confirm = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Take over as the teacher device?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This device replaces the current teacher device'
                  '${schoolName.isEmpty ? '' : ' for $schoolName'}. The old '
                  'device should not be used again.',
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirm,
                  onChanged: (_) => setLocal(() {}),
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Type TAKE OVER to confirm',
                    border: OutlineInputBorder(),
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
              onPressed:
                  confirm.text.trim().toUpperCase() == 'TAKE OVER' &&
                      pass.text.isNotEmpty
                  ? () => Navigator.pop(ctx, pass.text)
                  : null,
              child: const Text('Take over'),
            ),
          ],
        ),
      ),
    );
    pass.dispose();
    confirm.dispose();
    return result;
  }

  Future<void> _promote(Map<String, dynamic> ledger, String schoolName) async {
    final pass = await _askTakeOver(schoolName);
    if (pass == null || !mounted) return;
    setState(() => _busy = true);
    try {
      _service.stopMirroring();
      final r = await _service.promoteToHostNode(
        pass,
        ledger,
        ownerTeacherId: ref.read(activeTeacherIdProvider),
      );
      if (!mounted) return;
      if (!r.ok) {
        _message(r.error!);
        if (_ledger != null) _service.startMirroring(() => _endpoints);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This is now the teacher device'),
          content: Text(
            '${r.classes} ${r.classes == 1 ? 'class' : 'classes'} restored.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Open Class sync'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/teacher/sync');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promoteHeld() async {
    final ledger = await _service.storedLedger();
    if (!mounted) return;
    if (ledger == null) {
      _message('No backup on this device');
      return;
    }
    await _promote(ledger, _ledger?.schoolName ?? '');
  }

  Future<void> _promoteFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose the teacher-device backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    if (file == null || !mounted) return;
    Map<String, dynamic>? ledger;
    try {
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      final decoded = bytes == null ? null : jsonDecode(utf8.decode(bytes));
      if (decoded is Map) ledger = Map<String, dynamic>.from(decoded);
    } catch (_) {
      ledger = null;
    }
    if (!mounted) return;
    if (ledger == null) {
      _message('Not a valid backup file');
      return;
    }
    await _promote(ledger, '');
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final small = TextStyle(fontSize: 12, color: ac.textSecondary);
    final ledger = _ledger;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Standby device',
        subtitle: 'Backup and takeover',
        icon: Icons.backup_rounded,
        iconColor: AppColors.accentBlue,
        showBack: true,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : MaxWidth(
              maxWidth: 640,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (ledger == null)
                    _pairCard(ac, small)
                  else
                    _standbyCard(ac, small, ledger),
                  const SizedBox(height: 16),
                  StudioCard(
                    accent: AppColors.accentOrange,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replace the teacher device',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ac.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (ledger?.sealedJson != null)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accentOrange,
                                ),
                                onPressed: _busy ? null : _promoteHeld,
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Take over'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _promoteFromFile,
                              icon: const Icon(Icons.file_open_rounded),
                              label: const Text('Import backup file'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _pairCard(AppColors ac, TextStyle small) => StudioCard(
    accent: AppColors.accentBlue,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pair with the teacher device',
          style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Device name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Pairing code',
            hintText: 'K7M4-P9QX',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _address,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Teacher device address (optional)',
            hintText: '192.168.43.1',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _endpoints.isEmpty
              ? 'Searching…'
              : '${_endpoints.length} found',
          style: small,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _pair,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded),
          label: const Text('Pair'),
        ),
      ],
    ),
  );

  Widget _standbyCard(AppColors ac, TextStyle small, HostLedger ledger) =>
      StudioCard(
        accent: ledger.sealedJson == null
            ? AppColors.accentOrange
            : AppColors.accentGreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ledger.schoolName.isEmpty ? 'Paired' : ledger.schoolName,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ac.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ledger.receivedAt == null
                  ? 'No backup yet'
                  : 'Backed up ${failoverTime(ledger.receivedAt!)}',
              style: TextStyle(color: ac.textPrimary),
            ),
            if (_lastPullError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _lastPullError!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Teacher device address (optional)',
                hintText: '192.168.43.1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _backUpNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: const Text('Back up now'),
                ),
                TextButton(
                  onPressed: _busy ? null : _stopStandingBy,
                  child: const Text('Unpair'),
                ),
              ],
            ),
          ],
        ),
      );
}
