import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// The cryptography behind class sync — who may pull a class's notes, and
/// how a student's device knows the notes really came from its teacher.
///
/// * **Class key** — 32 random bytes per class/stream, minted on the
///   teacher's device and handed to a student device once, at join. Requests
///   are MAC'd with it and replies are encrypted with it, so a device that
///   never joined can neither ask nor read.
/// * **Teacher signing key** — one Ed25519 key pair per teacher device. Its
///   public half is pinned on the student device at join. Every reply is
///   signed with it, over a nonce the student chose for that request, so a
///   classmate (who also holds the class key) cannot pose as the teacher, and
///   an old reply cannot be replayed. No timestamps: school devices' clocks
///   are often wrong.
/// * **Join code** — short, typed by the student, never sent on the wire.
///   Both sides stretch it with PBKDF2 into a secret that proves the code
///   and encrypts the join bundle.

// ── Random bytes and encoding ──────────────────────────────────────────────

final _rng = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64(String s) {
  final padded = s.padRight((s.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

/// A fresh class key, as stored on both devices.
String newClassKey() => b64(randomBytes(32));

/// Per-request nonce, chosen by the student device.
String newNonce() => b64(randomBytes(16));

/// Compares two strings in time independent of where they first differ, so
/// a MAC check leaks nothing about how close a forged MAC came.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

// ── Teacher signing key ────────────────────────────────────────────────────

final _ed25519 = Ed25519();

/// A new signing seed (private) for this device. Store it; derive the public
/// key from it with [signingPublicKey].
String newSigningSeed() => b64(randomBytes(32));

Future<String> signingPublicKey(String seed) async {
  final pair = await _ed25519.newKeyPairFromSeed(unb64(seed));
  final pub = await pair.extractPublicKey();
  return b64(pub.bytes);
}

// ── Requests: MAC'd with the class key ─────────────────────────────────────

final _hmac = Hmac.sha256();

/// MAC over everything that identifies one request.
Future<String> requestMac({
  required String classKey,
  required String path,
  required String nonce,
  required String body,
}) async {
  final mac = await _hmac.calculateMac(
    utf8.encode('otic-sync-req-v1\n$path\n$nonce\n$body'),
    secretKey: SecretKey(unb64(classKey)),
  );
  return b64(mac.bytes);
}

// ── Replies: encrypted with the class key, signed by the teacher ───────────

final _aes = AesGcm.with256bits();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

Future<SecretKey> _replyKey(String classKey) => _hkdf.deriveKey(
  secretKey: SecretKey(unb64(classKey)),
  nonce: utf8.encode('otic-sync'),
  info: utf8.encode('otic-sync-reply-v1'),
);

List<int> _signedBytes(String requestNonce, String n, String c, String m) =>
    utf8.encode('otic-sync-reply-v1\n$requestNonce\n$n\n$c\n$m');

/// Encrypts [json] for the class and signs it for [requestNonce].
Future<Map<String, Object?>> sealReply({
  required String classKey,
  required String signingSeed,
  required String requestNonce,
  required Object? json,
}) async {
  final nonce = randomBytes(12);
  final box = await _aes.encrypt(
    utf8.encode(jsonEncode(json)),
    secretKey: await _replyKey(classKey),
    nonce: nonce,
    aad: utf8.encode(requestNonce),
  );
  final n = b64(box.nonce), c = b64(box.cipherText), m = b64(box.mac.bytes);
  final pair = await _ed25519.newKeyPairFromSeed(unb64(signingSeed));
  final sig = await _ed25519.sign(
    _signedBytes(requestNonce, n, c, m),
    keyPair: pair,
  );
  return {'v': 1, 'n': n, 'c': c, 'm': m, 's': b64(sig.bytes)};
}

/// Thrown when a reply is not from the pinned teacher, not for this request,
/// or not readable with the class key.
class SyncTrustError implements Exception {
  const SyncTrustError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Verifies [sealed] came from [teacherPublicKey] for [requestNonce], then
/// decrypts it. Throws [SyncTrustError] otherwise.
Future<Object?> openReply({
  required String classKey,
  required String teacherPublicKey,
  required String requestNonce,
  required Object? sealed,
}) async {
  if (sealed is! Map || sealed['v'] != 1) {
    throw const SyncTrustError('not a sealed reply');
  }
  final n = sealed['n'], c = sealed['c'], m = sealed['m'], s = sealed['s'];
  if (n is! String || c is! String || m is! String || s is! String) {
    throw const SyncTrustError('sealed reply is missing fields');
  }
  final ok = await _ed25519.verify(
    _signedBytes(requestNonce, n, c, m),
    signature: Signature(
      unb64(s),
      publicKey: SimplePublicKey(
        unb64(teacherPublicKey),
        type: KeyPairType.ed25519,
      ),
    ),
  );
  if (!ok) {
    throw const SyncTrustError('reply is not signed by this class’s teacher');
  }
  try {
    final clear = await _aes.decrypt(
      SecretBox(unb64(c), nonce: unb64(n), mac: Mac(unb64(m))),
      secretKey: await _replyKey(classKey),
      aad: utf8.encode(requestNonce),
    );
    return jsonDecode(utf8.decode(clear));
  } on SecretBoxAuthenticationError {
    throw const SyncTrustError(
      'reply could not be decrypted with the class key',
    );
  }
}

// ── Join codes ─────────────────────────────────────────────────────────────

/// No 0/O, 1/I: codes are read off a screen and typed on a phone.
const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 8 characters from 32 symbols — 40 bits, shown as `XXXX-XXXX`.
String newJoinCode() {
  final chars = List.generate(
    8,
    (_) => _codeAlphabet[_rng.nextInt(_codeAlphabet.length)],
  );
  return '${chars.take(4).join()}-${chars.skip(4).join()}';
}

/// What a student typed, reduced to the code's 8 characters — case, spaces
/// and hyphens don't matter. Null when it can't be a code.
String? normalizeJoinCode(String typed) {
  final s = typed.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (s.length != 8) return null;
  for (final ch in s.split('')) {
    if (!_codeAlphabet.contains(ch)) return null;
  }
  return s;
}

/// PBKDF2 rounds for a join code. Slow on purpose: a join is a one-off, and
/// every round multiplies the cost of guessing a code from a captured join.
const kJoinKdfRounds = 100000;

/// Stretches a normalized code (salted by the student's join nonce) into the
/// join secret. Runs off the UI isolate — it is deliberately slow.
Future<String> joinSecret(
  String normalizedCode,
  String salt, {
  int rounds = kJoinKdfRounds,
}) => Isolate.run(() => _joinSecret(normalizedCode, salt, rounds));

Future<String> _joinSecret(String code, String salt, int rounds) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: rounds,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(code)),
        nonce: utf8.encode('otic-join:$salt'),
      );
  return b64(await key.extractBytes());
}

/// Proof the student knows the code, without revealing it.
Future<String> joinProof(String secret, String salt) async {
  final mac = await _hmac.calculateMac(
    utf8.encode('otic-join-proof-v1\n$salt'),
    secretKey: SecretKey(unb64(secret)),
  );
  return b64(mac.bytes);
}

Future<SecretKey> _bundleKey(String secret) => _hkdf.deriveKey(
  secretKey: SecretKey(unb64(secret)),
  nonce: utf8.encode('otic-join'),
  info: utf8.encode('otic-join-bundle-v1'),
);

/// The class details, encrypted so only the device that typed the code can
/// read them.
Future<Map<String, Object?>> sealJoinBundle(
  String secret,
  String salt,
  Object? json,
) async {
  final box = await _aes.encrypt(
    utf8.encode(jsonEncode(json)),
    secretKey: await _bundleKey(secret),
    nonce: randomBytes(12),
    aad: utf8.encode(salt),
  );
  return {
    'n': b64(box.nonce),
    'c': b64(box.cipherText),
    'm': b64(box.mac.bytes),
  };
}

Future<Object?> openJoinBundle(
  String secret,
  String salt,
  Object? sealed,
) async {
  if (sealed is! Map) throw const SyncTrustError('not a join bundle');
  final n = sealed['n'], c = sealed['c'], m = sealed['m'];
  if (n is! String || c is! String || m is! String) {
    throw const SyncTrustError('join bundle is missing fields');
  }
  try {
    final clear = await _aes.decrypt(
      SecretBox(unb64(c), nonce: unb64(n), mac: Mac(unb64(m))),
      secretKey: await _bundleKey(secret),
      aad: utf8.encode(salt),
    );
    return jsonDecode(utf8.decode(clear));
  } on SecretBoxAuthenticationError {
    throw const SyncTrustError('join bundle could not be decrypted');
  }
}

// ── School tag ─────────────────────────────────────────────────────────────

/// A short tag for this device's school, announced on the network so a
/// device lists only its own school's learners and teachers. Filtering, not
/// security: the class key and the teacher's signature are what keep other
/// schools out. Null when the device has no school yet.
String? schoolTag(String? schoolId) => schoolId == null
    ? null
    : crypto.sha256
          .convert(utf8.encode('otic-school:$schoolId'))
          .toString()
          .substring(0, 12);

// ── Channel version ────────────────────────────────────────────────────────

/// A class+subject channel's version: a digest over its chunk hashes, in a
/// fixed order. Unlike the newest timestamp, it changes when a note is
/// removed or unshared, not only when one is added.
Future<String> channelDigest(Iterable<String> chunkIds) async {
  final sorted = chunkIds.toList()..sort();
  final hash = await Sha256().hash(utf8.encode(sorted.join('\n')));
  return b64(hash.bytes);
}
