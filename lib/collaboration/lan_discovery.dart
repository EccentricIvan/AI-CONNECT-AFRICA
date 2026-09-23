import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Discovers other AI Connect Africa learners on the same local network.
///
/// Uses UDP broadcast on the school LAN/Wi-Fi — no internet, no server.
/// Every device announces itself every few seconds; peers that go quiet
/// for [_peerTimeout] are dropped.
class LanPeer {
  const LanPeer({
    required this.id,
    required this.name,
    required this.topic,
    required this.points,
    required this.lastSeen,
    required this.address,
    this.role = 'student',
    this.syncPort,
  });

  final String id;
  final String name;
  final String topic;
  final int points;
  final DateTime lastSeen;
  final String address;

  /// 'student' (the default — every existing peer) or 'teacher'.
  final String role;

  /// Set only when [role] is 'teacher' and that device's
  /// `TeacherSyncServer` is running — the port a student's
  /// `SelectiveSyncManager` should call at [address].
  final int? syncPort;

  bool get isSyncServer => role == 'teacher' && syncPort != null;
}

class LanDiscoveryService {
  LanDiscoveryService({
    required this.displayName,
    this.currentTopic = '',
    this.points = 0,
    this.role = 'student',
    this.syncPort,
  });

  static const _port = 47474;
  static const _announceInterval = Duration(seconds: 3);
  static const _peerTimeout = Duration(seconds: 12);

  final String displayName;
  String currentTopic;
  int points;

  /// 'student' (default) or 'teacher' — announced so a `SelectiveSyncManager`
  /// can pick out sync servers from the same broadcast that already carries
  /// classmate presence, instead of a second discovery mechanism.
  final String role;

  /// The `TeacherSyncServer` port, when [role] is 'teacher' and it is
  /// running. Left null (and therefore un-announced) otherwise.
  int? syncPort;

  /// Random per-session ID so we can ignore our own broadcasts.
  final String _selfId =
      Random().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  final Map<String, LanPeer> _peers = {};
  final _controller = StreamController<List<LanPeer>>.broadcast();

  /// Live list of nearby learners, updated as announcements arrive/expire.
  Stream<List<LanPeer>> get peers => _controller.stream;

  bool get isRunning => _socket != null;

  /// Starts announcing and listening. Throws [SocketException] if the
  /// network is unavailable (caller should show a friendly message).
  Future<void> start() async {
    if (_socket != null) return;

    final socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port);
    socket.broadcastEnabled = true;
    _socket = socket;

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      _handlePacket(dg);
    });

    _announceTimer =
        Timer.periodic(_announceInterval, (_) => _announce());
    _pruneTimer = Timer.periodic(const Duration(seconds: 4), (_) => _prune());
    _announce();
  }

  void _announce() {
    final socket = _socket;
    if (socket == null) return;
    final payload = jsonEncode({
      'app': 'ai_connect_africa',
      'id': _selfId,
      'name': displayName,
      'topic': currentTopic,
      'points': points,
      'role': role,
      if (syncPort != null) 'sync_port': syncPort,
    });
    try {
      socket.send(
        utf8.encode(payload),
        InternetAddress('255.255.255.255'),
        _port,
      );
    } on SocketException {
      // Network dropped mid-session — peers will simply expire.
    }
  }

  void _handlePacket(Datagram dg) {
    try {
      final data = jsonDecode(utf8.decode(dg.data));
      if (data is! Map || data['app'] != 'ai_connect_africa') return;
      final id = data['id'] as String?;
      if (id == null || id == _selfId) return;

      _peers[id] = LanPeer(
        id: id,
        name: (data['name'] as String?) ?? 'Learner',
        topic: (data['topic'] as String?) ?? '',
        points: (data['points'] as num?)?.toInt() ?? 0,
        lastSeen: DateTime.now(),
        address: dg.address.address,
        role: (data['role'] as String?) ?? 'student',
        syncPort: (data['sync_port'] as num?)?.toInt(),
      );
      _emit();
    } catch (_) {
      // Ignore malformed packets — anything could be on this port.
    }
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(_peerTimeout);
    final before = _peers.length;
    _peers.removeWhere((_, p) => p.lastSeen.isBefore(cutoff));
    if (_peers.length != before) _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    final list = _peers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _controller.add(list);
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _socket?.close();
    _socket = null;
    _peers.clear();
    if (!_controller.isClosed) _controller.add(const []);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
