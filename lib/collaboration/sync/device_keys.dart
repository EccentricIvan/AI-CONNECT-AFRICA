import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'class_crypto.dart';

/// A device's own keys, beside its Ed25519 signing key:
///
///  * every Sync request is also signed with the signing key, so a sharer
///    knows *which* device is asking and can refuse a revoked one;
///  * an X25519 box key lets a sharer hand a new class key to each device
///    it still trusts, sealed so a revoked device can't read it.

/// Request header naming the asking device (its Ed25519 public key).
const kDeviceHeader = 'x-otic-device';

/// Request header with that device's signature over the request.
const kDeviceSigHeader = 'x-otic-device-sig';

final _ed25519 = Ed25519();
final _x25519 = X25519();
final _aes = AesGcm.with256bits();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

/// A new X25519 seed (private) for this device.
String newBoxSeed() => b64(randomBytes(32));

Future<String> boxPublicKey(String boxSeed) async {
  final pair = await _x25519.newKeyPairFromSeed(unb64(boxSeed));
  return b64((await pair.extractPublicKey()).bytes);
}

List<int> _requestBytes(String path, String nonce, String body) =>
    utf8.encode('otic-device-req-v1\n$path\n$nonce\n$body');

/// This device's signature over one request.
Future<String> signDeviceRequest({
  required String signingSeed,
  required String path,
  required String nonce,
  required String body,
}) async {
  final pair = await _ed25519.newKeyPairFromSeed(unb64(signingSeed));
  final sig = await _ed25519.sign(
    _requestBytes(path, nonce, body),
    keyPair: pair,
  );
  return b64(sig.bytes);
}

/// True when [signature] over the request is [deviceKey]'s.
Future<bool> verifyDeviceRequest({
  required String deviceKey,
  required String signature,
  required String path,
  required String nonce,
  required String body,
}) async {
  try {
    return await _ed25519.verify(
      _requestBytes(path, nonce, body),
      signature: Signature(
        unb64(signature),
        publicKey: SimplePublicKey(unb64(deviceKey), type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

Future<SecretKey> _boxKey(SecretKey shared, List<int> ephemeralPub) =>
    _hkdf.deriveKey(
      secretKey: shared,
      nonce: ephemeralPub,
      info: utf8.encode('otic-device-box-v1'),
    );

/// Seals [json] so only the device whose box key is [recipientBoxKey] can
/// open it: a fresh X25519 key agreement per message, AES-GCM.
Future<Map<String, Object?>> sealToDevice({
  required String recipientBoxKey,
  required Object? json,
}) async {
  final eph = await _x25519.newKeyPair();
  final ephPub = (await eph.extractPublicKey()).bytes;
  final shared = await _x25519.sharedSecretKey(
    keyPair: eph,
    remotePublicKey: SimplePublicKey(
      unb64(recipientBoxKey),
      type: KeyPairType.x25519,
    ),
  );
  final box = await _aes.encrypt(
    utf8.encode(jsonEncode(json)),
    secretKey: await _boxKey(shared, ephPub),
    nonce: randomBytes(12),
  );
  return {
    'e': b64(ephPub),
    'n': b64(box.nonce),
    'c': b64(box.cipherText),
    'm': b64(box.mac.bytes),
  };
}

/// Opens what [sealToDevice] sealed to this device. Throws
/// [SyncTrustError] when it wasn't sealed to [boxSeed]'s key or was changed.
Future<Object?> openSealedToDevice({
  required String boxSeed,
  required Object? sealed,
}) async {
  if (sealed is! Map) throw const SyncTrustError('sealed key is malformed');
  final e = sealed['e'], n = sealed['n'], c = sealed['c'], m = sealed['m'];
  if (e is! String || n is! String || c is! String || m is! String) {
    throw const SyncTrustError('sealed key is malformed');
  }
  try {
    final me = await _x25519.newKeyPairFromSeed(unb64(boxSeed));
    final ephPub = unb64(e);
    final shared = await _x25519.sharedSecretKey(
      keyPair: me,
      remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519),
    );
    final clear = await _aes.decrypt(
      SecretBox(unb64(c), nonce: unb64(n), mac: Mac(unb64(m))),
      secretKey: await _boxKey(shared, ephPub),
    );
    return jsonDecode(utf8.decode(clear));
  } on SyncTrustError {
    rethrow;
  } catch (_) {
    throw const SyncTrustError('sealed key did not open');
  }
}
