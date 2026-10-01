import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android only: keeps this device sharing while the app is off screen,
/// through a foreground service with Wi-Fi and wake locks
/// (`android/.../ClassShareService.kt`). A no-op everywhere else, since
/// desktop processes aren't frozen in the background.
///
/// Reference-counted: one device can share as teacher and as classmate at
/// once, and the service stops only when the last [ClassShareServer] does.
/// Best-effort: if Android refuses, sharing still works while the app stays
/// on screen, exactly as before this existed.
class ShareKeepAlive {
  ShareKeepAlive._();

  static const _channel = MethodChannel('ai_connect_africa/class_share');
  static int _holders = 0;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> acquire() async {
    if (!_supported) return;
    if (_holders++ > 0) return;
    try {
      await _channel.invokeMethod<bool>('start');
    } catch (e) {
      debugPrint('Class sharing keep-alive not started: $e');
    }
  }

  static Future<void> release() async {
    if (!_supported || _holders == 0) return;
    if (--_holders > 0) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('Class sharing keep-alive not stopped: $e');
    }
  }
}
