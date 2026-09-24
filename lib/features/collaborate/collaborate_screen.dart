import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/lan_discovery.dart';
import '../../collaboration/sync/mdns_discovery.dart';
import '../../collaboration/sync/selective_sync_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../teacher/class_providers.dart';

class CollaborateScreen extends ConsumerStatefulWidget {
  const CollaborateScreen({super.key});

  @override
  ConsumerState<CollaborateScreen> createState() => _CollaborateScreenState();
}

class _CollaborateScreenState extends ConsumerState<CollaborateScreen> {
  LanDiscoveryService? _service;
  final MdnsSyncDiscovery _mdns = MdnsSyncDiscovery();
  List<LanPeer> _peers = const [];
  List<MdnsSyncPeer> _mdnsPeers = const [];
  String? _error;
  bool _starting = true;

  /// UDP and mDNS peers, merged and deduplicated by (address, sync port) —
  /// the same teacher server answering on both channels must show once, not
  /// twice.
  List<LanPeer> get _allPeers {
    final seen = <String>{
      for (final p in _peers)
        if (p.isSyncServer) '${p.address}:${p.syncPort}',
    };
    final combined = [..._peers];
    for (final m in _mdnsPeers) {
      final key = '${m.address}:${m.port}';
      if (seen.add(key)) {
        combined.add(LanPeer(
          id: 'mdns:$key',
          name: m.name,
          topic: '',
          points: 0,
          lastSeen: DateTime.now(),
          address: m.address,
          role: 'teacher',
          syncPort: m.port,
        ));
      }
    }
    return combined;
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (kIsWeb) {
      setState(() {
        _starting = false;
        _error =
            'Local network discovery is not available in the web '
            'preview. Use the Windows, Linux, or Android app.';
      });
      return;
    }

    final student = await ref.read(activeStudentProvider.future);
    final service = LanDiscoveryService(
      displayName: student?.name ?? 'Learner',
      points: student?.totalPoints ?? 0,
    );

    // Best-effort, additive discovery — mDNS is unsupported on Linux/web
    // (see MdnsSyncDiscovery doc) and never blocks UDP presence either way.
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
        setState(() {
          _service = service;
          _starting = false;
        });
      }
    } on SocketException catch (e) {
      service.dispose();
      if (mounted) {
        setState(() {
          _starting = false;
          _error =
              'Could not join the local network (${e.osError?.message ?? e.message}). '
              'Make sure this device is connected to the school Wi-Fi or LAN.';
        });
      }
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    unawaited(_mdns.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(activeStudentProvider);
    final classesAsync = ref.watch(classGroupsProvider);
    final myClassGroupId = studentAsync.valueOrNull?.classGroupId;
    ClassGroup? myClass;
    if (myClassGroupId != null) {
      for (final c in classesAsync.valueOrNull ?? const <ClassGroup>[]) {
        if (c.id == myClassGroupId) {
          myClass = c;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Nearby learners'),
        subtitle: tr(context, 'Discover classmates on this network'),
        icon: Icons.wifi_tethering_rounded,
        iconColor: AppColors.accentCyan,
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: _starting
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!)
            : _PeersView(peers: _allPeers, myClass: myClass),
      ),
    );
  }
}

class _PeersView extends ConsumerWidget {
  const _PeersView({required this.peers, required this.myClass});
  final List<LanPeer> peers;
  final ClassGroup? myClass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncPeers = peers.where((p) => p.isSyncServer).toList();
    final learnerPeers = peers.where((p) => !p.isSyncServer).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (syncPeers.isNotEmpty) ...[
          _SyncSection(peers: syncPeers, myClass: myClass),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 4),
        ],
        // Status banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.practiceColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.practiceColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  learnerPeers.isEmpty
                      ? 'Searching for learners on your local network…'
                      : '${learnerPeers.length} learner${learnerPeers.length == 1 ? '' : 's'} nearby',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'You can see who is nearby on the same Wi-Fi or LAN, and pull '
            'class material a teacher is syncing (above, when available). '
            'General project sharing between learners is not available yet — '
            'no internet needed for any of this.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),

        if (learnerPeers.isEmpty)
          const _EmptyPeers()
        else
          ...learnerPeers.map((p) => _PeerCard(peer: p)),
      ],
    );
  }
}

/// Teacher devices on this network currently syncing a class, and this
/// student's own "Sync now" action — shown only when both exist: a sync
/// server nobody is assigned to, or a learner with no class assigned, has
/// nothing useful to offer here.
class _SyncSection extends ConsumerStatefulWidget {
  const _SyncSection({required this.peers, required this.myClass});
  final List<LanPeer> peers;
  final ClassGroup? myClass;

  @override
  ConsumerState<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<_SyncSection> {
  String? _syncingPeerId;
  final Map<String, SyncResult> _results = {};

  Future<void> _syncFrom(LanPeer peer) async {
    final group = widget.myClass;
    if (group == null || group.groupUuid == null || _syncingPeerId != null) {
      return;
    }
    setState(() => _syncingPeerId = peer.id);
    final manager = SelectiveSyncManager(ref.read(dbProvider));
    try {
      final result = await manager.syncClass(
        teacherAddress: peer.address,
        teacherPort: peer.syncPort!,
        classGroupUuid: group.groupUuid!,
      );
      if (!mounted) return;
      setState(() => _results[peer.id] = result);
    } finally {
      manager.dispose();
      if (mounted) setState(() => _syncingPeerId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final group = widget.myClass;

    if (group == null) {
      return const _SyncNotice(
        text: 'A teacher is syncing class material nearby, but you are not '
            'assigned to a class yet — ask your teacher to add you under '
            'Teacher → Classes.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Class sync available',
          style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
        ),
        const SizedBox(height: 8),
        for (final peer in widget.peers) ...[
          _SyncPeerCard(
            peer: peer,
            myClassLabel: classLabel(group),
            syncing: _syncingPeerId == peer.id,
            result: _results[peer.id],
            onSync: () => _syncFrom(peer),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.accentOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4))),
        ],
      ),
    );
  }
}

class _SyncPeerCard extends StatelessWidget {
  const _SyncPeerCard({
    required this.peer,
    required this.myClassLabel,
    required this.syncing,
    required this.result,
    required this.onSync,
  });

  final LanPeer peer;
  final String myClassLabel;
  final bool syncing;
  final SyncResult? result;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final r = result;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentTeal.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_tethering_rounded, color: AppColors.accentTeal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${peer.name} — $myClassLabel',
                  style: TextStyle(fontWeight: FontWeight.w600, color: ac.textPrimary),
                ),
              ),
              FilledButton.tonal(
                onPressed: syncing ? null : onSync,
                child: syncing
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sync now'),
              ),
            ],
          ),
          if (r != null) ...[
            const SizedBox(height: 8),
            Text(
              r.ok
                  ? '${r.chunksInserted} new note${r.chunksInserted == 1 ? '' : 's'} pulled '
                      'across ${r.subjectsChecked} subject${r.subjectsChecked == 1 ? '' : 's'}'
                      '${r.rejected.isEmpty ? '' : ' — ${r.rejected.length} rejected'}.'
                  : r.error!,
              style: TextStyle(
                fontSize: 12,
                color: r.ok ? ac.textSecondary : Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer});
  final LanPeer peer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        title: Text(
          peer.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          peer.topic.isNotEmpty
              ? 'Learning: ${peer.topic}'
              : 'Online · ${peer.address}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars, color: Colors.amber, size: 16),
            const SizedBox(width: 4),
            Text(
              '${peer.points}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.wifi_tethering, size: 56, color: Theme.of(context).hintColor),
          const SizedBox(height: 16),
          const Text(
            'No learners found yet',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask a classmate to open the app on the same network — '
            'they will appear here within a few seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 56, color: Theme.of(context).hintColor),
            const SizedBox(height: 16),
            const Text(
              'Local network unavailable',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: AppColors.practiceColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
