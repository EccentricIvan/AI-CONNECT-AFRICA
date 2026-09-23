import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hashKey = 'teacher_pin_hash';
const _saltKey = 'teacher_pin_salt';

/// One shared PIN per device guarding the Teacher and Admin areas.
///
/// This keeps a curious learner on a shared classroom device out of the
/// class lists and the lesson materials. It is a classroom lock, not
/// security: a 4–8 digit PIN can be brute-forced by anyone who can copy the
/// app's files, and there is no account behind it. Only a salted hash is
/// stored, so the PIN itself is never readable from the preferences file.
///
/// With no PIN set nothing is gated — existing installs behave as before
/// until a teacher opts in.
class TeacherPin {
  static final _format = RegExp(r'^\d{4,8}$');

  static bool isValidFormat(String pin) => _format.hasMatch(pin);

  Future<bool> isSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hashKey) != null;
  }

  Future<void> set(String pin) async {
    if (!isValidFormat(pin)) {
      throw ArgumentError('A PIN is 4 to 8 digits.');
    }
    final rng = Random.secure();
    final salt =
        base64Url.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(salt, pin));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
  }

  /// True when [pin] is right — or when no PIN is set at all.
  Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_hashKey);
    final salt = prefs.getString(_saltKey);
    if (hash == null || salt == null) return true;
    return _hash(salt, pin) == hash;
  }

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}

final teacherPinProvider = Provider((ref) => TeacherPin());

/// Whether the teacher has entered the PIN in this app session.
///
/// In memory only, so the lock returns on restart, and cleared whenever the
/// device is handed to a learner (see `LearnerSwitcher`).
final teacherUnlockedProvider = StateProvider<bool>((ref) => false);

/// Routes behind the PIN.
bool isTeacherRoute(String location) =>
    location == '/teacher' ||
    location.startsWith('/teacher/') ||
    location == '/admin' ||
    location.startsWith('/admin/');

/// Where the router should send a request for [uri], or null to let it
/// through: a locked teacher route goes to the PIN screen, carrying the
/// original destination so the teacher lands where they were going.
String? teacherGateRedirect(
  Uri uri, {
  required bool unlocked,
  required bool pinSet,
}) {
  if (!pinSet || unlocked || !isTeacherRoute(uri.path)) return null;
  return Uri(path: '/unlock', queryParameters: {'to': uri.toString()})
      .toString();
}
