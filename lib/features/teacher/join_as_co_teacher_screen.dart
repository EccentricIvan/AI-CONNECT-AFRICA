import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collaboration/lan_discovery.dart';
import '../../collaboration/sync/class_crypto.dart';
import '../../collaboration/sync/mdns_discovery.dart';
import '../../collaboration/sync/selective_sync_manager.dart';
import '../../collaboration/sync/sync_address.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/studio_page.dart';
import 'class_providers.dart';
import 'co_teacher_widgets.dart';

/// A teacher device joining another teacher's class as a co-teacher — with
/// an invite code that teacher made for specific subjects — and the list of
/// classes this device already co-teaches.
///
/// A co-teacher shares only its own subjects' notes, from this device
/// (Lesson materials → Share with classes, then Class sync → Start sharing).
/// Students still join through the class's own teacher.
class JoinAsCoTeacherScreen extends ConsumerStatefulWidget {
  const JoinAsCoTeacherScreen({super.key});

  @override
  ConsumerState<JoinAsCoTeacherScreen> createState() =>
      _JoinAsCoTeacherScreenState();
}

class _JoinAsCoTeacherScreenState extends ConsumerState<JoinAsCoTeacherScreen> {
  LanDiscoveryService? _service;
  final MdnsSyncDiscovery _mdns = MdnsSyncDiscovery();
  List<LanPeer> _peers = const [];
  List<MdnsSyncPeer> _mdnsPeers = const [];
  String? _myTag;

  final _code = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _address.dispose();
    _service?.dispose();
    unawaited(_mdns.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    if (kIsWeb) return;
    final me = await ref.read(dbProvider).classSyncDao.identity();
    if (!mounted) return;
    _myTag = schoolTag(me.schoolId);
    final service = LanDiscoveryService(
      displayName: 'Teacher',
      role: 'teacher',
      schoolTag: _myTag,
    );
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
        setState(() => _service = service);
      } else {
        service.dispose();
      }
    } on SocketException {
      service.dispose();
    }
  }

  /// Teacher devices seen on the network (this school's only, once this
  /// device has one), then the typed address.
  List<TeacherEndpoint> get _endpoints {
    final found = <TeacherEndpoint>[];
    final seen = <String>{};
    void add(TeacherEndpoint e) {
      if (seen.add('${e.address}:${e.port}')) found.add(e);
    }

    for (final p in _peers) {
      final visible = _myTag == null
          ? p.isSyncServer
          : p.isSyncServer && p.schoolTag == _myTag;
      if (visible) add((address: p.address, port: p.syncPort!));
    }
    for (final m in _mdnsPeers) {
      add((address: m.address, port: m.port));
    }
    final typed = parseTeacherAddress(_address.text);
    if (typed != null) add(typed);
    return found;
  }

  Future<void> _join() async {
    if (_busy || _code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final manager = SelectiveSyncManager(ref.read(dbProvider));
    try {
      final r = await manager.joinAsCoTeacher(
        roots: _endpoints,
        typedCode: _code.text,
        name: _name.text.trim(),
      );
      if (!mounted) return;
      _message(
        r.ok
            ? 'You now co-teach this class. Add your notes in Lesson '
                  'materials, share them with the class, then start sharing '
                  'it from Class sync.'
            : r.error!,
      );
      if (r.ok) _code.clear();
    } finally {
      manager.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(CoTeachingClass c) async {
    if (_busy) return;
    setState(() => _busy = true);
    final manager = SelectiveSyncManager(ref.read(dbProvider));
    try {
      final ok = await manager.refreshDelegatedClass(
        roots: _endpoints,
        delegated: c,
      );
      if (!mounted) return;
      _message(
        ok
            ? 'Up to date with ${delegatedClassLabel(c)}’s teacher.'
            : 'Couldn’t reach ${delegatedClassLabel(c)}’s teacher. Make sure '
                  'their device is sharing the class.',
      );
    } finally {
      manager.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(CoTeachingClass c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop co-teaching ${delegatedClassLabel(c)}?'),
        content: const Text(
          'This device stops sharing into that class. Ask its teacher to '
          'revoke you too, so students stop expecting your notes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(dbProvider)
        .coTeacherDao
        .deleteDelegatedClass(c.classGroupUuid);
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

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final delegated =
        ref.watch(delegatedClassesProvider).valueOrNull ??
        const <CoTeachingClass>[];
    final names = subjectNames(ref);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const StudioAppBar(
        title: 'Co-teach a class',
        subtitle: 'Share your own subject’s notes into another teacher’s class',
        icon: Icons.group_add_rounded,
        iconColor: AppColors.accentBlue,
        showBack: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StudioCard(
            accent: AppColors.accentBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Join with an invite code',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ac.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The class’s teacher makes the code on their device (Class '
                  'sync → Teachers on this class → Invite a co-teacher) and '
                  'taps Accept when your name appears.',
                  style: TextStyle(fontSize: 12, color: ac.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Your name, as the teacher will see it',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Invite code, e.g. K7M4-P9QX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _address,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Teacher’s address (only if not found)',
                    hintText: '192.168.43.1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _endpoints.isEmpty
                      ? 'No teacher device found yet.'
                      : 'Teacher devices found: ${_endpoints.length}',
                  style: TextStyle(fontSize: 12, color: ac.textSecondary),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _join,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: const Text('Join as co-teacher'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Classes you co-teach',
            style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
          ),
          const SizedBox(height: 8),
          if (delegated.isEmpty)
            Text(
              'None yet.',
              style: TextStyle(color: ac.textSecondary),
            ),
          for (final c in delegated)
            StudioCard(
              accent: AppColors.accentTeal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    delegatedClassLabel(c),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ac.textPrimary,
                    ),
                  ),
                  Text(
                    delegatedSubjects(c).isEmpty
                        ? 'No subjects — the class’s teacher revoked you.'
                        : 'You teach: ${delegatedSubjects(c).map(names).join(', ')}',
                    style: TextStyle(fontSize: 12, color: ac.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : () => _refresh(c),
                        child: const Text('Check for changes'),
                      ),
                      TextButton(
                        onPressed: () => _leave(c),
                        child: const Text('Stop co-teaching'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
