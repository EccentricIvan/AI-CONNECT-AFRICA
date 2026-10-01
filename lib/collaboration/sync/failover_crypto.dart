import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

import 'class_crypto.dart';

/// The cryptography behind host failover (`p2p_failover_service.dart`).
///
/// * **Ledger key** — stretched from the teacher's failover passphrase with
///   PBKDF2-HMAC-SHA256. The host derives it once and keeps it; a standby
///   never has it until someone types the passphrase at promotion.
/// * **Host ledger** — everything a standby needs to become the host,
///   including the host's Ed25519 signing seed, AES-GCM encrypted under the
///   ledger key. Its plain header (school, host public key, generation, KDF
///   salt and rounds) is bound in as associated data, so it can't be edited.
///   It is never encrypted with a class key: classmates hold those.
/// * **Standby pairing** — a typed code plus the teacher's Accept, as with a
///   co-teacher, binding the standby's own public key. After that the
///   standby signs each ledger request with its own key, and the host signs
///   each reply with the school's root key over the standby's nonce.

const kLedgerFormat = 'otic-host-ledger-v1';

/// PBKDF2 rounds for the ledger key. Much higher than a join code's
/// ([kJoinKdfRounds]): a stolen standby database can be attacked offline
/// for as long as the attacker likes, and this runs once per enable or
/// promotion, not once per learner.
const kLedgerKdfRounds = 600000;

/// Shortest passphrase accepted. Length matters more than symbols here,
/// because the passphrase is all that protects the ledger on a standby.
const kMinPassphraseLength = 12;

final _aes = AesGcm.with256bits();
final _ed25519 = Ed25519();

/// Stretches [passphrase] into the ledger key, off the UI isolate.
Future<String> deriveLedgerKey(
  String passphrase,
  String salt, {
  int rounds = kLedgerKdfRounds,
}) => Isolate.run(() async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: rounds,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(passphrase)),
        nonce: utf8.encode('otic-ledger:$salt'),
      );
  return b64(await key.extractBytes());
});

/// The ledger's plain header, as associated data — every field a reader
/// trusts before decrypting is covered by the GCM tag.
List<int> _ledgerAad(Map<String, Object?> h) => utf8.encode(
  [
    h['format'],
    h['school_id'],
    h['root_public_key'],
    h['generation'],
    h['created_at'],
    (h['kdf'] as Map)['rounds'],
    (h['kdf'] as Map)['salt'],
  ].join('\n'),
);

/// Seals [inner] into a host ledger under [ledgerKey].
Future<Map<String, Object?>> sealLedger({
  required String ledgerKey,
  required String salt,
  required int rounds,
  required String schoolId,
  required String rootPublicKey,
  required int generation,
  required Map<String, Object?> inner,
}) async {
  final header = <String, Object?>{
    'format': kLedgerFormat,
    'school_id': schoolId,
    'root_public_key': rootPublicKey,
    'generation': generation,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'kdf': {'alg': 'pbkdf2-hmac-sha256', 'rounds': rounds, 'salt': salt},
  };
  final box = await _aes.encrypt(
    utf8.encode(jsonEncode(inner)),
    secretKey: SecretKey(unb64(ledgerKey)),
    nonce: randomBytes(12),
    aad: _ledgerAad(header),
  );
  return {
    ...header,
    'n': b64(box.nonce),
    'c': b64(box.cipherText),
    'm': b64(box.mac.bytes),
  };
}

/// The ledger's plain header, checked for shape. Null when [ledger] isn't
/// one — the same answer for a bad shape as for a wrong passphrase is not
/// needed here: nothing secret is learned from the header.
({
  String schoolId,
  String rootPublicKey,
  int generation,
  String salt,
  int rounds,
})?
ledgerHeader(Map<String, Object?> ledger) {
  final kdf = ledger['kdf'];
  if (ledger['format'] != kLedgerFormat || kdf is! Map) return null;
  final school = ledger['school_id'], root = ledger['root_public_key'];
  final gen = ledger['generation'];
  final salt = kdf['salt'], rounds = kdf['rounds'];
  if (school is! String ||
      root is! String ||
      gen is! int ||
      gen < 0 ||
      salt is! String ||
      rounds is! int ||
      rounds < 1 ||
      ledger['created_at'] is! String ||
      ledger['n'] is! String ||
      ledger['c'] is! String ||
      ledger['m'] is! String) {
    return null;
  }
  return (
    schoolId: school,
    rootPublicKey: root,
    generation: gen,
    salt: salt,
    rounds: rounds,
  );
}

/// Decrypts [ledger] with [ledgerKey]. Throws [SyncTrustError] when the key
/// is wrong or anything in the ledger (header included) was altered.
Future<Map<String, Object?>> openLedger(
  Map<String, Object?> ledger,
  String ledgerKey,
) async {
  try {
    final clear = await _aes.decrypt(
      SecretBox(
        unb64(ledger['c'] as String),
        nonce: unb64(ledger['n'] as String),
        mac: Mac(unb64(ledger['m'] as String)),
      ),
      secretKey: SecretKey(unb64(ledgerKey)),
      aad: _ledgerAad(ledger),
    );
    final inner = jsonDecode(utf8.decode(clear));
    if (inner is! Map) throw const SyncTrustError('ledger is not an object');
    return Map<String, Object?>.from(inner);
  } on SecretBoxAuthenticationError {
    throw const SyncTrustError('wrong passphrase, or the backup was altered');
  }
}

// ── Standby pairing and mirroring ──────────────────────────────────────────

/// Proof a standby knows the pairing code, binding its own public key so the
/// key can't be swapped in transit (as [coTeacherJoinProof] does).
Future<String> standbyPairProof(
  String secret,
  String salt,
  String standbyPublicKey,
) async {
  final mac = await Hmac.sha256().calculateMac(
    utf8.encode('otic-standby-pair-proof-v1\n$salt\n$standbyPublicKey'),
    secretKey: SecretKey(unb64(secret)),
  );
  return b64(mac.bytes);
}

Future<String> _sign(String seed, List<int> message) async {
  final pair = await _ed25519.newKeyPairFromSeed(unb64(seed));
  return b64((await _ed25519.sign(message, keyPair: pair)).bytes);
}

Future<bool> _verify(String publicKey, List<int> message, String sig) async {
  try {
    return await _ed25519.verify(
      message,
      signature: Signature(
        unb64(sig),
        publicKey: SimplePublicKey(unb64(publicKey), type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

Future<List<int>> _requestBytes(String path, String nonce, String body) async {
  final hash = await Sha256().hash(utf8.encode(body));
  return utf8.encode('otic-standby-request-v1\n$path\n$nonce\n${b64(hash.bytes)}');
}

/// A standby's signature over one ledger request.
Future<String> signStandbyRequest({
  required String standbySeed,
  required String path,
  required String nonce,
  required String body,
}) async => _sign(standbySeed, await _requestBytes(path, nonce, body));

Future<bool> verifyStandbyRequest({
  required String standbyPublicKey,
  required String path,
  required String nonce,
  required String body,
  required String signature,
}) async => _verify(
  standbyPublicKey,
  await _requestBytes(path, nonce, body),
  signature,
);

Future<List<int>> _replyBytes(String nonce, String ledgerJson) async {
  final hash = await Sha256().hash(utf8.encode(ledgerJson));
  return utf8.encode('otic-ledger-reply-v1\n$nonce\n${b64(hash.bytes)}');
}

/// The host's root-key signature over a ledger reply, bound to the
/// standby's nonce — so a device on the Wi-Fi can't feed a standby a
/// bogus or replayed ledger that would only fail at promotion time.
Future<String> signLedgerReply({
  required String rootSeed,
  required String nonce,
  required String ledgerJson,
}) async => _sign(rootSeed, await _replyBytes(nonce, ledgerJson));

Future<bool> verifyLedgerReply({
  required String rootPublicKey,
  required String nonce,
  required String ledgerJson,
  required String signature,
}) async => _verify(
  rootPublicKey,
  await _replyBytes(nonce, ledgerJson),
  signature,
);
