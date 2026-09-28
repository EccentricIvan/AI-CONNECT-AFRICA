import 'dart:io';

import 'selective_sync_manager.dart' show TeacherEndpoint;
import 'class_share_server.dart' show kDefaultSyncPort;

/// This device's Wi-Fi/LAN IPv4 addresses, for a teacher to read out when
/// students' devices can't find the teacher automatically (phone hotspots and
/// some school Wi-Fi block the broadcast discovery uses).
Future<List<String>> localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
final _hostname = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$');

/// Reads a teacher address a student typed — `192.168.43.1`, or
/// `192.168.43.1:8765` — into an endpoint. Null when it isn't one. The port
/// defaults to [kDefaultSyncPort].
TeacherEndpoint? parseTeacherAddress(String typed) {
  var text = typed.trim();
  text = text.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  text = text.replaceFirst(RegExp(r'/+$'), '');
  if (text.isEmpty) return null;

  var host = text;
  var port = kDefaultSyncPort;
  final colon = text.lastIndexOf(':');
  if (colon != -1) {
    host = text.substring(0, colon);
    final parsed = int.tryParse(text.substring(colon + 1));
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    port = parsed;
  }
  if (_ipv4.hasMatch(host)) {
    final ok = host.split('.').every((p) => int.parse(p) <= 255);
    return ok ? (address: host, port: port) : null;
  }
  return _hostname.hasMatch(host) ? (address: host, port: port) : null;
}
