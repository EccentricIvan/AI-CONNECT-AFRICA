import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/lan_discovery.dart';
import '../../collaboration/sync/class_share_server.dart';
import '../../collaboration/sync/selective_sync_manager.dart';
import '../../collaboration/sync/sync_address.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/studio_page.dart';
import '../teacher/class_providers.dart';
import 'join_requests.dart';

/// A student passing the teacher's notes on to classmates who missed the
/// teacher. Only classmates who already joined the class through the
/// teacher can take anything, only after this student taps Accept, and
/// they get the teacher's notes exactly as signed — nothing this device
/// could change.
class ShareWithClassmatesCard extends ConsumerStatefulWidget {
  const ShareWithClassmatesCard({
    super.key,
    required this.group,
    required this.discovery,
  });

  final ClassGroup group;

  /// The screen's own discovery socket — switched to announce this share.
  final LanDiscoveryService? discovery;

  @override
  ConsumerState<ShareWithClassmatesCard> createState() =>
      _ShareWithClassmatesCardState();
}

class _ShareWithClassmatesCardState
    extends ConsumerState<ShareWithClassmatesCard> {
  ClassShareServer? _server;
  String? _code;
  List<String> _addresses = const [];
  String? _note;
  bool _starting = false;

  bool get _running => _server?.isRunning ?? false;

  @override
  void dispose() {
    _server?.dispose();
    _announce(null);
    super.dispose();
  }

  void _announce(int? port) {
    final d = widget.discovery;
    if (d == null) return;
    d.role = port == null ? 'student' : 'classmate';
    d.syncPort = port;
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _note = null;
    });
    final db = ref.read(dbProvider);
    try {
      final uuid = widget.group.groupUuid!;
      if ((await db.classSyncDao.relayableChannels(uuid)).isEmpty) {
        setState(
          () => _note =
              'Sync with your teacher first — you can only pass on notes you '
              'have received.',
        );
        return;
      }
      final server = ClassShareServer(db, role: ShareRole.classmate);
      final port = await server.start(classUuids: {uuid});
      final code = await server.openJoinCode(widget.group);
      final addresses = await localIPv4Addresses();
      if (!mounted) {
        server.dispose();
        return;
      }
      _announce(port);
      setState(() {
        _server = server;
        _code = code;
        _addresses = [
          for (final a in addresses) port == kDefaultSyncPort ? a : '$a:$port',
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not start sharing: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final s = _server;
    setState(() {
      _server = null;
      _code = null;
    });
    _announce(null);
    s?.dispose();
  }

  Future<void> _newCode() async {
    final code = await _server?.openJoinCode(widget.group);
    if (mounted) setState(() => _code = code);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return StudioCard(
      accent: AppColors.accentViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share with classmates',
            style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Pass your teacher’s notes for ${classLabel(widget.group)} to a '
            'classmate who missed the sync. They must have joined the class '
            'with the teacher’s code. Keep this screen open while sharing.',
            style: TextStyle(fontSize: 12, color: ac.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _starting ? null : (_running ? _stop : _start),
            icon: Icon(_running ? Icons.stop_rounded : Icons.share_rounded),
            label: Text(_running ? 'Stop sharing' : 'Start sharing'),
          ),
          if (_note != null) ...[
            const SizedBox(height: 8),
            Text(_note!, style: const TextStyle(fontSize: 12.5)),
          ],
          if (_running) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SelectableText(
                  _code ?? '—',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                  ),
                ),
                IconButton(
                  tooltip: 'New code',
                  onPressed: _newCode,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Text(
              'Your classmate types this code (valid 30 minutes).'
              '${_addresses.isEmpty ? '' : ' If their device can’t find yours, '
                        'they type this address: ${_addresses.join(' or ')}'}',
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
            const SizedBox(height: 10),
            JoinRequestsCard(server: _server!),
          ],
        ],
      ),
    );
  }
}

/// Getting the teacher's notes from a classmate who is sharing them.
class GetFromClassmateCard extends ConsumerStatefulWidget {
  const GetFromClassmateCard({
    super.key,
    required this.group,
    required this.found,
    required this.learnerName,
  });

  final ClassGroup group;

  /// Classmates seen sharing on the network.
  final List<TeacherEndpoint> found;
  final String learnerName;

  @override
  ConsumerState<GetFromClassmateCard> createState() =>
      _GetFromClassmateCardState();
}

class _GetFromClassmateCardState extends ConsumerState<GetFromClassmateCard> {
  final _code = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void dispose() {
    _code.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _get() async {
    final typed = _address.text.trim();
    final manual = typed.isEmpty ? null : parseTeacherAddress(typed);
    if (typed.isNotEmpty && manual == null) {
      setState(() {
        _status = 'That address doesn’t look right. Try 192.168.43.12';
        _statusIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Waiting for your classmate to tap Accept…';
      _statusIsError = false;
    });
    final manager = SelectiveSyncManager(ref.read(dbProvider));
    try {
      final joined = await manager.joinClassmate(
        classmates: [...widget.found, ?manual],
        typedCode: _code.text,
        name: widget.learnerName,
      );
      if (!joined.ok) {
        if (mounted) {
          setState(() {
            _status = joined.error;
            _statusIsError = true;
          });
        }
        return;
      }
      if (mounted) setState(() => _status = 'Getting notes…');
      final r = await manager.syncFromClassmate(joined.session!);
      if (!mounted) return;
      setState(() {
        _statusIsError = !r.ok;
        _status = !r.ok
            ? r.error
            : r.subjectsUpdated == 0 && r.rejected.isEmpty
            ? 'You already have everything your classmate has.'
            : 'Got ${r.subjectsUpdated} subject${r.subjectsUpdated == 1 ? '' : 's'} '
                  'of your teacher’s notes'
                  '${r.rejected.isEmpty ? '' : ' — ${r.rejected.length} didn’t match '
                            'what your teacher signed and were skipped'}.';
      });
      _code.clear();
    } finally {
      manager.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return StudioCard(
      accent: AppColors.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get notes from a classmate',
            style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            widget.found.isEmpty
                ? 'Missed your teacher? Ask a classmate to tap Share with '
                      'classmates, then type the code they show.'
                : '${widget.found.length} classmate'
                      '${widget.found.length == 1 ? ' is' : 's are'} sharing '
                      'nearby. Type the code they show.',
            style: TextStyle(fontSize: 12, color: ac.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'K7M4-P9QX',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Classmate’s address (optional)',
              hintText: '192.168.43.12',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy || _code.text.trim().isEmpty ? null : _get,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: const Text('Get notes'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: TextStyle(
                fontSize: 12.5,
                color: _statusIsError ? Colors.red : ac.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
