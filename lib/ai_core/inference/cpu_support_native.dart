import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

bool get cpuSupportsLlamaCpp => _supported ??= _detect();
bool? _supported;

bool _detect() {
  var supported = true;
  try {
    if (Platform.isWindows) supported = _windowsHasAvx2();
    if (Platform.isLinux) supported = _linuxHasAvx2();
  } catch (e) {
    // A failed probe must not take the AI away from a capable machine.
    debugPrint('cpu_support: AVX2 probe failed, assuming supported: $e');
  }
  if (!supported) {
    debugPrint('cpu_support: no AVX2 on this CPU — llama.cpp models stay off.');
  }
  // Android and other ARM targets ship builds without the AVX2 requirement.
  return supported;
}

// winnt.h
const _pfAvxInstructionsAvailable = 39;
const _pfAvx2InstructionsAvailable = 40;
const _xstateMaskAvx = 1 << 2;

bool _windowsHasAvx2() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final enabledXStateFeatures = kernel32
      .lookupFunction<Uint64 Function(), int Function()>(
        'GetEnabledXStateFeatures',
      );
  // No AVX register state at all, so AVX2 code cannot run.
  if ((enabledXStateFeatures() & _xstateMaskAvx) == 0) return false;

  final isProcessorFeaturePresent = kernel32
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IsProcessorFeaturePresent',
      );
  // Windows builds that predate PF_AVX* answer false for both. AVX is on
  // (checked above), so false here means "can't tell", not "no".
  if (isProcessorFeaturePresent(_pfAvxInstructionsAvailable) == 0) return true;
  return isProcessorFeaturePresent(_pfAvx2InstructionsAvailable) != 0;
}

bool _linuxHasAvx2() {
  final cpuinfo = File('/proc/cpuinfo').readAsStringSync();
  final flags = RegExp(r'^flags\s*:(.*)$', multiLine: true)
      .firstMatch(cpuinfo)
      ?.group(1);
  // No x86 flags line (ARM Linux), so not the AVX2 build.
  if (flags == null) return true;
  return flags.split(RegExp(r'\s+')).contains('avx2');
}
