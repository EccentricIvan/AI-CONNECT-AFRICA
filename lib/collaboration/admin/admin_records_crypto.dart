import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../sync/class_crypto.dart';
import '../sync/failover_crypto.dart';

/// Format tag of a signed bundle of the Admin's school records.
const kAdminRecordsFormat = 'otic-admin-records-v1';

final _ed25519 = Ed25519();
final _aes = AesGcm.with256bits();

/// Signs [payload] (the exact JSON text sent) with the Admin's key.
Future<String> signAdminRecords(String seed, String payload) async {
  final pair = await _ed25519.newKeyPairFromSeed(unb64(seed));
  return b64(
    (await _ed25519.sign(utf8.encode(payload), keyPair: pair)).bytes,
  );
}

/// Whether [sig] is [publicKey]'s signature over [payload].
Future<bool> verifyAdminRecords(
  String publicKey,
  String payload,
  String sig,
) async {
  try {
    return await _ed25519.verify(
      utf8.encode(payload),
      signature: Signature(
        unb64(sig),
        publicKey: SimplePublicKey(unb64(publicKey), type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

/// The Admin's own details (signing key, name, PIN hash), sealed under a
/// passphrase so the Admin can take over on the receiving device. Without
/// the passphrase the receiver can't read them.
Future<Map<String, Object?>> sealAdminTakeover({
  required String passphrase,
  required Map<String, Object?> admin,
  int rounds = kLedgerKdfRounds,
}) async {
  final salt = newNonce();
  final key = await deriveLedgerKey(passphrase, salt, rounds: rounds);
  final box = await _aes.encrypt(
    utf8.encode(jsonEncode(admin)),
    secretKey: SecretKey(unb64(key)),
    nonce: randomBytes(12),
    aad: utf8.encode('otic-admin-takeover-v1\n$salt\n$rounds'),
  );
  return {
    'salt': salt,
    'rounds': rounds,
    'n': b64(box.nonce),
    'c': b64(box.cipherText),
    'm': b64(box.mac.bytes),
  };
}

/// The Admin's details from [sealed], or null when [passphrase] is wrong
/// or the seal was tampered with.
Future<Map<String, Object?>?> openAdminTakeover({
  required String passphrase,
  required Map<String, Object?> sealed,
}) async {
  final salt = sealed['salt'], rounds = sealed['rounds'];
  final n = sealed['n'], c = sealed['c'], m = sealed['m'];
  if (salt is! String ||
      rounds is! int ||
      n is! String ||
      c is! String ||
      m is! String) {
    return null;
  }
  try {
    final key = await deriveLedgerKey(passphrase, salt, rounds: rounds);
    final clear = await _aes.decrypt(
      SecretBox(unb64(c), nonce: unb64(n), mac: Mac(unb64(m))),
      secretKey: SecretKey(unb64(key)),
      aad: utf8.encode('otic-admin-takeover-v1\n$salt\n$rounds'),
    );
    final json = jsonDecode(utf8.decode(clear));
    return json is Map<String, Object?> ? json : null;
  } catch (_) {
    return null;
  }
}
