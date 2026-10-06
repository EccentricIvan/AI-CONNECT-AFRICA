import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../collaboration/lan_discovery.dart';
import '../../collaboration/sync/class_crypto.dart' show schoolTag;
import '../../collaboration/sync/mdns_discovery.dart';
import '../../collaboration/sync/selective_sync_manager.dart';
import '../../collaboration/sync/sync_address.dart';
import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../services/custom_subject_service.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/studio_page.dart';
import '../teacher/class_providers.dart';
import 'classmate_share_cards.dart';

const _manualAddressKey = 'class_sync_teacher_address';

/// The learner's side of class sync: type the teacher's join code once, then
/// tap Sync now to pull the class's shared notes.
///
/// Works on any device on the teacher's Wi-Fi/hotspot — a phone, a PC — and
/// needs no teacher login: the join code and the class key it hands over are
/// what decide who gets notes (see `SelectiveSyncManager`).
///
/// The teacher's device is found automatically when the network allows it.
/// Phone hotspots and some school Wi-Fi block that, so the teacher's address
/// can also be typed in by hand.
class ClassSyncScreen extends ConsumerStatefulWidget {
  const ClassSyncScreen({super.key});

  @override
  ConsumerState<ClassSyncScreen> createState() => _ClassSyncScreenState();
}

class _ClassSyncScreenState extends ConsumerState<ClassSyncScreen> {
  LanDiscoveryService? _service;
  final MdnsSyncDiscovery _mdns = MdnsSyncDiscovery();
  List<LanPeer> _peers = const [];
  List<MdnsSyncPeer> _mdnsPeers = const [];
  String? _myTag;
  String? _discoveryNote;

  final _code = TextEditingController();
  final _address = TextEditingController();
  bool _joining = false;
  bool _syncing = false;
  SyncResult? _result;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    _address.dispose();
    _service?.dispose();
    unawaited(_mdns.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _address.text = prefs.getString(_manualAddressKey) ?? '';
    } catch (_) {}
    if (kIsWeb) {
      setState(
        () => _discoveryNote =
            'Finding the teacher automatically isn’t available in the web '
            'preview. Type the teacher’s address below.',
      );
      return;
    }

    final student = await ref.read(activeStudentProvider.future);
    final me = await ref.read(dbProvider).classSyncDao.identity();
    if (!mounted) return;
    _myTag = schoolTag(me.schoolId);
    final service = LanDiscoveryService(
      displayName: student?.name ?? 'Learner',
      points: student?.totalPoints ?? 0,
      schoolTag: _myTag,
    );

    // Best-effort, additive — mDNS is unsupported on Linux/web (see
    // MdnsSyncDiscovery) and never blocks UDP discovery either way.
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
    } on SocketException catch (e) {
      service.dispose();
      if (mounted) {
        setState(
          () => _discoveryNote =
              'Couldn’t look for the teacher on this network '
              '(${e.osError?.message ?? e.message}). Check the Wi-Fi is on, or '
              'type the teacher’s address below.',
        );
      }
    }
  }

  /// Teachers seen on the network, then the typed address. Deduplicated by
  /// (address, port) — one teacher answers on both UDP and mDNS.
  List<TeacherEndpoint> get _endpoints {
    final found = <TeacherEndpoint>[];
    final seen = <String>{};
    void add(TeacherEndpoint e) {
      if (seen.add('${e.address}:${e.port}')) found.add(e);
    }

    for (final p in _peers) {
      // With a school, only that school's teachers; without one (never
      // joined a class) every teacher, so the learner can join.
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

  /// Classmates of this school sharing their teacher's notes nearby.
  List<TeacherEndpoint> get _classmates => [
    for (final p in _peers)
      if (p.isClassmateShare && (_myTag == null || p.schoolTag == _myTag))
        (address: p.address, port: p.syncPort!),
  ];

  bool get _addressInvalid =>
      _address.text.trim().isNotEmpty &&
      parseTeacherAddress(_address.text) == null;

  Future<void> _rememberAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final typed = parseTeacherAddress(_address.text);
      if (typed == null) return;
      await prefs.setString(_manualAddressKey, _address.text.trim());
    } catch (_) {}
  }

  Future<void> _join() async {
    if (_code.text.trim().isEmpty || _joining) return;
    if (_addressInvalid) {
      _message('That teacher address doesn’t look right. Try 192.168.43.1');
      return;
    }
    setState(() => _joining = true);
    final manager = SelectiveSyncManager(ref.read(dbProvider));
    try {
      final me = await ref.read(activeStudentProvider.future);
      final result = await manager.joinClass(
        teachers: _endpoints,
        typedCode: _code.text,
        name: me?.name ?? '',
      );
      if (!mounted) return;
      if (!result.ok) {
        _message(result.error!);
        return;
      }
      unawaited(_rememberAddress());
      final student = await ref.read(activeStudentProvider.future);
      if (student != null) {
        await ref
            .read(dbProvider)
            .classGroupDao
            .assignLearner(student.id, result.group!.id);
        ref.invalidate(activeStudentProvider);
      }
      if (!mounted) return;
      _code.clear();
      setState(() {
        _result = null;
        _syncError = null;
      });
      _message(
        'Joined ${classLabel(result.group!)}'
        '${(result.schoolName ?? '').isEmpty ? '' : ' at ${result.schoolName}'}. '
        'Tap Sync now to get your class notes.',
      );
    } finally {
      manager.dispose();
      if (mounted) setState(() => _joining = false);
    }
  }

  /// Syncs with every teacher device found — the class's own teacher and any
  /// co-teachers, each of which only carries its own subjects. Every reply
  /// is checked against keys this device already trusts for the class (the
  /// teacher's, pinned at join, and the co-teachers in its signed roster),
  /// so a wrong or fake device can only fail, never feed this one notes.
  Future<void> _syncNow(ClassGroup group) async {
    if (_syncing) return;
    if (_addressInvalid) {
      _message('That teacher address doesn’t look right. Try 192.168.43.1');
      return;
    }
    final endpoints = _endpoints;
    if (endpoints.isEmpty) {
      setState(() {
        _result = null;
        _syncError =
            'No teacher device found';
      });
      return;
    }
    setState(() {
      _syncing = true;
      _result = null;
      _syncError = null;
    });
    final manager = SelectiveSyncManager(ref.read(dbProvider));
    try {
      final last = await manager.syncClassEverywhere(
        candidates: endpoints,
        group: group,
      );
      if (!mounted) return;
      unawaited(_rememberAddress());
      // The teacher's subject list may have changed, and PDFs may have come.
      ref.invalidate(customSubjectsProvider);
      setState(() {
        if (last.ok) {
          _result = last;
        } else {
          _syncError = last.error;
        }
      });
    } finally {
      manager.dispose();
      if (mounted) setState(() => _syncing = false);
    }
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

  static String _summary(SyncResult r) {
    final reported = r.learnersReported == 0
        ? ''
        : ' Your progress was sent to your teacher.';
    final pdfs = r.pdfsFetched == 0
        ? ''
        : ' ${r.pdfsFetched} PDF${r.pdfsFetched == 1 ? '' : 's'} downloaded.';
    return _notesSummary(r) + pdfs + reported;
  }

  static String _notesSummary(SyncResult r) {
    final s = r.subjectsChecked;
    final subjects = '$s subject${s == 1 ? '' : 's'}';
    if (r.subjectsUpdated == 0 &&
        r.subjectsRemoved == 0 &&
        r.rejected.isEmpty) {
      return 'Up to date — $subjects.';
    }
    final removed = r.subjectsRemoved == 0
        ? ''
        : ', removed ${r.subjectsRemoved} no longer shared';
    final problems = r.rejected.isEmpty
        ? ''
        : ' — ${r.rejected.length} problem${r.rejected.length == 1 ? '' : 's'}, '
              'those kept as they were';
    return 'Updated ${r.subjectsUpdated} of $subjects$removed$problems.';
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final studentAsync = ref.watch(activeStudentProvider);
    final classes = ref.watch(classGroupsProvider).valueOrNull ?? const [];
    final classId = studentAsync.valueOrNull?.classGroupId;
    ClassGroup? group;
    for (final c in classes) {
      if (c.id == classId) group = c;
    }
    final joined = group != null && group.joined;
    final endpoints = _endpoints;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: StudioAppBar(
        title: tr(context, 'Sync'),
        subtitle: tr(context, 'Class notes'),
        icon: Icons.sync_rounded,
        iconColor: AppColors.accentTeal,
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (joined) ...[
              StudioCard(
                accent: AppColors.accentTeal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My class: ${classLabel(group)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ac.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      endpoints.isEmpty
                          ? 'Waiting for teacher…'
                          : '${endpoints.length} teacher device'
                                '${endpoints.length == 1 ? '' : 's'} nearby.',
                      style: TextStyle(fontSize: 12, color: ac.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _syncing ? null : () => _syncNow(group!),
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Sync now'),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _summary(_result!),
                        style: TextStyle(fontSize: 12.5, color: ac.textSecondary),
                      ),
                    ],
                    if (_syncError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _syncError!,
                        style: const TextStyle(fontSize: 12.5, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              if (studentAsync.valueOrNull case final me?) ...[
                const SizedBox(height: 16),
                _MySubjectsCard(studentId: me.id, learnerName: me.name),
              ],

              const SizedBox(height: 16),
              GetFromClassmateCard(
                group: group,
                found: _classmates,
                learnerName: studentAsync.valueOrNull?.name ?? '',
              ),
              const SizedBox(height: 16),
              ShareWithClassmatesCard(group: group, discovery: _service),
              const SizedBox(height: 16),
            ],
            StudioCard(
              accent: AppColors.accentOrange,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    joined ? 'Join a different class' : 'Join your class',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ac.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'K7M4-P9QX',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _join(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _joining || _code.text.trim().isEmpty
                        ? null
                        : _join,
                    icon: _joining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.vpn_key_outlined, size: 18),
                    label: Text(
                      _joining
                          ? 'Waiting for approval…'
                          : 'Join class',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StudioCard(
              accent: AppColors.accentCyan,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  initiallyExpanded: _address.text.trim().isNotEmpty,
                  title: Text(
                    'Enter address manually',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: ac.textPrimary,
                    ),
                  ),
                  children: [
                    TextField(
                      controller: _address,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Teacher device address',
                        hintText: '192.168.43.1',
                        border: const OutlineInputBorder(),
                        errorText: _addressInvalid
                            ? 'Invalid address'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (_discoveryNote != null) ...[
              const SizedBox(height: 12),
              Text(
                _discoveryNote!,
                style: TextStyle(fontSize: 12, color: ac.textSecondary),
              ),
            ],
            if (!kIsWeb && Platform.isWindows) ...[
              const SizedBox(height: 16),
              Text(
                'If Windows asks, allow network access.',
                style: TextStyle(fontSize: 12, color: ac.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The subjects a learner says they take — every built-in subject plus the
/// ones their teacher made. It arrives with the learner's progress, and on
/// a student device it decides whose notes they may read (`note_access.dart`).
class _MySubjectsCard extends ConsumerWidget {
  const _MySubjectsCard({required this.studentId, required this.learnerName});

  final int studentId;
  final String learnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = AppColors.of(context);
    final subjects = ref.watch(mergedSubjectsProvider).valueOrNull ?? const [];
    final enrolled =
        ref.watch(enrolledSubjectsProvider(studentId)).valueOrNull ?? const {};
    final dao = ref.read(dbProvider).classSyncDao;

    return StudioCard(
      accent: AppColors.accentGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My subjects',
            style: TextStyle(fontWeight: FontWeight.w700, color: ac.textPrimary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in subjects)
                FilterChip(
                  label: Text(s.name),
                  selected: enrolled.contains(s.id),
                  onSelected: (on) => dao.setEnrolled(studentId, s.id, on),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
