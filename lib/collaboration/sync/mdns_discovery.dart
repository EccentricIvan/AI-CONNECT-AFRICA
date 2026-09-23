import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

/// One [TeacherSyncServer] found via mDNS/NSD.
class MdnsSyncPeer {
  const MdnsSyncPeer({
    required this.name,
    required this.address,
    required this.port,
  });

  final String name;
  final String address;
  final int port;
}

/// mDNS/DNS-SD (Bonjour) discovery for [TeacherSyncServer], additive to the
/// UDP broadcast [LanDiscoveryService] already does for classmate presence
/// — not a replacement for it.
///
/// Two reasons this stays a second, optional channel rather than replacing
/// the UDP one:
///  * platform coverage — `nsd` backs Android, iOS, macOS and Windows, but
///    ships no Linux implementation, and this app explicitly targets
///    Ubuntu (CLAUDE.md). [isSupported] is false there, and every method on
///    this class silently no-ops rather than throwing, so a caller can wire
///    it in unconditionally and it simply contributes nothing on Linux/web
///    while [LanDiscoveryService] keeps working everywhere.
///  * mDNS multicast is blocked or flaky on some school/hotspot routers
///    (client-isolation APs, some Android hotspots) in exactly the way UDP
///    broadcast on this app's own fixed port usually is not — so the two
///    are complementary discovery paths for the same server, not two
///    sources of truth to reconcile.
class MdnsSyncDiscovery {
  static const _serviceType = '_otic-sync._tcp';

  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  nsd.ServiceListener? _listener;

  final Map<String, MdnsSyncPeer> _peers = {};
  final _controller = StreamController<List<MdnsSyncPeer>>.broadcast();

  /// Live list of teacher sync servers found on this network.
  Stream<List<MdnsSyncPeer>> get peers => _controller.stream;

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  /// Announces this device's running [TeacherSyncServer] over mDNS.
  /// A no-op (not an error) on an unsupported platform.
  Future<void> registerServer({
    required String className,
    required int port,
  }) async {
    if (!isSupported) return;
    try {
      _registration = await nsd.register(
        nsd.Service(
          name: 'OTIC Sync - $className',
          type: _serviceType,
          port: port,
        ),
      );
    } catch (e, st) {
      debugPrint('mDNS registerServer failed (continuing on UDP only): $e\n$st');
    }
  }

  Future<void> unregisterServer() async {
    final registration = _registration;
    if (registration == null) return;
    _registration = null;
    try {
      await nsd.unregister(registration);
    } catch (e) {
      debugPrint('mDNS unregisterServer failed (ignored): $e');
    }
  }

  /// Starts listening for other devices' [registerServer] announcements.
  Future<void> startDiscovering() async {
    if (!isSupported || _discovery != null) return;
    try {
      final discovery = await nsd.startDiscovery(
        _serviceType,
        ipLookupType: nsd.IpLookupType.any,
      );
      _discovery = discovery;

      void listener(nsd.Service service, nsd.ServiceStatus status) {
        final id = '${service.name}@${service.type}';
        if (status == nsd.ServiceStatus.lost) {
          if (_peers.remove(id) != null) _emit();
          return;
        }
        final address = service.addresses?.isNotEmpty ?? false
            ? service.addresses!.first.address
            : service.host;
        final port = service.port;
        if (address == null || port == null) return; // Not resolved yet.
        _peers[id] = MdnsSyncPeer(
          name: service.name ?? 'Teacher',
          address: address,
          port: port,
        );
        _emit();
      }

      _listener = listener;
      discovery.addServiceListener(listener);
      // Seed with whatever autoResolve already picked up before this
      // listener was attached.
      for (final service in discovery.services) {
        listener(service, nsd.ServiceStatus.found);
      }
    } catch (e, st) {
      debugPrint('mDNS startDiscovering failed (continuing on UDP only): $e\n$st');
    }
  }

  Future<void> stopDiscovering() async {
    final discovery = _discovery;
    final listener = _listener;
    _discovery = null;
    _listener = null;
    if (discovery == null) return;
    try {
      if (listener != null) discovery.removeServiceListener(listener);
      await nsd.stopDiscovery(discovery);
    } catch (e) {
      debugPrint('mDNS stopDiscovering failed (ignored): $e');
    }
    _peers.clear();
    _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_peers.values.toList());
  }

  Future<void> dispose() async {
    await unregisterServer();
    await stopDiscovering();
    if (!_controller.isClosed) await _controller.close();
  }
}
