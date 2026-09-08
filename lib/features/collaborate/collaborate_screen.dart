import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/lan_discovery.dart';
import '../../core/theme/app_colors.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';

class CollaborateScreen extends ConsumerStatefulWidget {
  const CollaborateScreen({super.key});

  @override
  ConsumerState<CollaborateScreen> createState() => _CollaborateScreenState();
}

class _CollaborateScreenState extends ConsumerState<CollaborateScreen> {
  LanDiscoveryService? _service;
  List<LanPeer> _peers = const [];
  String? _error;
  bool _starting = true;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
appBar: StudioAppBar(
        title: tr(context, 'Nearby learners'),
        subtitle: tr(context, 'Discover classmates on this network'),
        icon: Icons.wifi_tethering_rounded,
        iconColor: const Color(0xFF2EB8A0),
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: _starting
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!)
            : _PeersView(peers: _peers),
      ),
    );
  }
}

class _PeersView extends StatelessWidget {
  const _PeersView({required this.peers});
  final List<LanPeer> peers;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                  peers.isEmpty
                      ? 'Searching for learners on your local network…'
                      : '${peers.length} learner${peers.length == 1 ? '' : 's'} nearby',
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
            'Discovery only for now: you can see who is nearby on the same '
            'Wi-Fi or LAN. Project sharing and sync are not available yet — '
            'no internet needed for discovery.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),

        if (peers.isEmpty)
          const _EmptyPeers()
        else
          ...peers.map((p) => _PeerCard(peer: p)),
      ],
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
