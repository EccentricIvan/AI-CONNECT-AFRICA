import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Total RAM in GB, or null when it could not be read (then the AI is
/// tried anyway — a failed probe must not take it from a capable device).
double? get deviceMemoryGb => _memory ??= _detect();
double? _memory;

double? _detect() {
  try {
    if (Platform.isWindows) return _windowsTotalGb();
    if (Platform.isLinux || Platform.isAndroid) return _procMeminfoGb();
  } catch (e) {
    debugPrint('memory_support: probe failed: $e');
  }
  return null;
}

/// `MemTotal:  3805228 kB` from /proc/meminfo.
double? _procMeminfoGb() {
  for (final line in File('/proc/meminfo').readAsLinesSync()) {
    if (!line.startsWith('MemTotal:')) continue;
    final kb = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
    return kb == null ? null : kb / (1024 * 1024);
  }
  return null;
}

/// GlobalMemoryStatusEx's ullTotalPhys.
final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

double? _windowsTotalGb() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final status = kernel32
      .lookupFunction<
        Int32 Function(Pointer<_MemoryStatusEx>),
        int Function(Pointer<_MemoryStatusEx>)
      >('GlobalMemoryStatusEx');
  final p = calloc<_MemoryStatusEx>();
  try {
    p.ref.dwLength = sizeOf<_MemoryStatusEx>();
    if (status(p) == 0) return null;
    return p.ref.ullTotalPhys / (1024 * 1024 * 1024);
  } finally {
    calloc.free(p);
  }
}
