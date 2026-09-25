import 'dart:io';

import 'package:flutter/foundation.dart';

/// How much memory this device has, and what that means for the models.
///
/// A "4 GB" phone reports ~3.5–3.8 GB in `/proc/meminfo` (the rest is
/// reserved by the firmware), so anything under 5 GB is treated as the
/// low-memory tier the app is built for.
///
/// On that tier:
/// * LiteRT-LM starts on its CPU backend instead of probing NPU/GPU. A GPU
///   compile of a 1.5B model runs out of memory on these phones (Google's
///   own Pixel 8a note), wastes seconds, and can take the app down before
///   the "remember what worked" step ever saves — a crash loop on every
///   launch. The student can still ask for the GPU in Settings.
class DeviceTier {
  DeviceTier._(this.totalBytes);

  /// Null when the platform does not expose it.
  final int? totalBytes;

  static const lowMemoryLimitBytes = 5 * 1024 * 1024 * 1024;

  static DeviceTier? _cached;

  static DeviceTier get current => _cached ??= DeviceTier._(_readTotalBytes());

  @visibleForTesting
  static DeviceTier fromMeminfo(String meminfo) =>
      DeviceTier._(parseMemTotalBytes(meminfo));

  @visibleForTesting
  static void overrideForTesting(DeviceTier? tier) => _cached = tier;

  /// True on the ~4 GB phones this app targets. Unknown memory counts as low:
  /// assuming too little costs a little speed, assuming too much can crash.
  bool get isLowMemory {
    final t = totalBytes;
    if (t == null) return true;
    return t < lowMemoryLimitBytes;
  }

  String get label {
    final t = totalBytes;
    final gb = t == null ? '?' : (t / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return isLowMemory ? 'Low-memory phone ($gb GB)' : 'Phone with $gb GB';
  }

  static int? _readTotalBytes() {
    if (kIsWeb) return null;
    try {
      final f = File('/proc/meminfo');
      if (!f.existsSync()) return null;
      return parseMemTotalBytes(f.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// `MemTotal:  3812344 kB` → bytes.
  @visibleForTesting
  static int? parseMemTotalBytes(String meminfo) {
    final m = RegExp(r'^MemTotal:\s+(\d+)\s*kB', multiLine: true).firstMatch(meminfo);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 1024;
  }
}
