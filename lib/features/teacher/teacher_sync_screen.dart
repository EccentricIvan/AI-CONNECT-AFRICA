import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/lan_discovery.dart';
import '../../collaboration/sync/mdns_discovery.dart';
import '../../collaboration/sync/teacher_sync_server.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/studio_page.dart';
import 'class_providers.dart';

/// Starts/stops this device's [TeacherSyncServer] for one class/stream, so
/// student devices on the same Wi-Fi/hotspot can pull that class's material.
///
/// Server and discovery announcement are started and stopped together: a
/// server nobody can find is useless, and announcing a sync port for a
/// server that is not actually listening would send students to a dead
/// connection.
class TeacherSyncScreen extends ConsumerStatefulWidget {
  const TeacherSyncScreen({super.key});

  @override
  ConsumerState<TeacherSyncScreen> createState() => _TeacherSyncScreenState();
}

class _TeacherSyncScreenState extends ConsumerState<TeacherSyncScreen> {
  TeacherSyncServer? _server;
  LanDiscoveryService? _announcer;
  final MdnsSyncDiscovery _mdns = MdnsSyncDiscovery();
  ClassGroup? _selected;
  bool _starting = false;
  String? _error;

  bool get _running => _server?.isRunning ?? false;

  @override
  void dispose() {
    _server?.stop();
    _announcer?.dispose();
    _mdns.dispose();
    super.dispose();
  }

  Future<void> _toggle(List<ClassGroup> classes) async {
    if (_running) {
      await _server?.stop();
      _announcer?.dispose();
      await _mdns.unregisterServer();
      setState(() {
        _server = null;
        _announcer = null;
      });
      return;
    }

    final group = _selected;
    if (group == null || group.groupUuid == null) {
      setState(() => _error =
          'This class has no sync id yet — reopen the Teacher tab once, '
          'then try again.');
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final db = ref.read(dbProvider);
      final server = TeacherSyncServer(db);
      final port = await server.start();

      final announcer = LanDiscoveryService(
        displayName: 'Teacher · ${classLabel(group)}',
        role: 'teacher',
        syncPort: port,
      );
      await announcer.start();
      // Additive — MdnsSyncDiscovery no-ops on Linux/web (see its doc), so
      // UDP announcement above is the one path guaranteed to work here.
      await _mdns.registerServer(className: classLabel(group), port: port);

      if (!mounted) {
        await server.stop();
        announcer.dispose();
        await _mdns.unregisterServer();
        return;
      }
      setState(() {
        _server = server;
        _announcer = announcer;
      });
    } catch (e) {
      setState(() => _error = 'Could not start the sync server: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classGroupsProvider);
    final ac = AppColors.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Class sync',
        subtitle: 'Push this class’s material to student devices',
        icon: Icons.sync_rounded,
        iconColor: AppColors.accentTeal,
        showBack: true,
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (classes) {
          if (classes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Create a class/stream first (Teacher → Add class), '
                  'then come back here to sync its material.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _selected ??= classes.first;
          final selected =
              classes.firstWhere((c) => c.id == _selected!.id, orElse: () => classes.first);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Class to sync',
                style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: selected.id,
                items: [
                  for (final c in classes)
                    DropdownMenuItem(value: c.id, child: Text(classLabel(c))),
                ],
                onChanged: _running
                    ? null
                    : (id) => setState(
                        () => _selected = classes.firstWhere((c) => c.id == id)),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              StudioCard(
                accent: _running ? AppColors.accentGreen : AppColors.accentSlate,
                child: Row(
                  children: [
                    Icon(
                      _running ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                      color: _running ? AppColors.accentGreen : ac.textHint,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _running
                            ? 'Broadcasting ${classLabel(selected)} on port ${_server!.port} — '
                                'students on this Wi-Fi/hotspot can sync now.'
                            : 'Not syncing. Students cannot pull material until '
                                'you start this.',
                        style: TextStyle(color: ac.textPrimary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _starting ? null : () => _toggle(classes),
                icon: _starting
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(_running ? 'Stop syncing' : 'Start syncing this class'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              Text(
                'This only works over the same Wi-Fi/hotspot, with no internet '
                'involved — a device outside this network cannot reach it. '
                'Anyone on the network can pull this class’s material while '
                'it is running, the same trust level as Nearby learners.',
                style: TextStyle(fontSize: 12, color: ac.textSecondary, height: 1.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
