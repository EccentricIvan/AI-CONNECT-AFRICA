import 'package:ai_connect_africa/collaboration/sync/class_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('replies', () {
    late String classKey, seed, pub;
    setUp(() async {
      classKey = newClassKey();
      seed = newSigningSeed();
      pub = await signingPublicKey(seed);
    });

    test('the class opens what its teacher sealed', () async {
      final nonce = newNonce();
      final sealed = await sealReply(
        classKey: classKey,
        signingSeed: seed,
        requestNonce: nonce,
        json: {'a': 1},
      );
      expect(
        await openReply(
          classKey: classKey,
          teacherPublicKey: pub,
          requestNonce: nonce,
          sealed: sealed,
        ),
        {'a': 1},
      );
    });

    test('a classmate with the class key cannot pose as the teacher', () async {
      final nonce = newNonce();
      final forged = await sealReply(
        classKey: classKey,
        signingSeed: newSigningSeed(),
        requestNonce: nonce,
        json: {},
      );
      expect(
        () => openReply(
          classKey: classKey,
          teacherPublicKey: pub,
          requestNonce: nonce,
          sealed: forged,
        ),
        throwsA(isA<SyncTrustError>()),
      );
    });

    test('an old reply cannot be replayed for a new request', () async {
      final sealed = await sealReply(
        classKey: classKey,
        signingSeed: seed,
        requestNonce: newNonce(),
        json: {},
      );
      expect(
        () => openReply(
          classKey: classKey,
          teacherPublicKey: pub,
          requestNonce: newNonce(),
          sealed: sealed,
        ),
        throwsA(isA<SyncTrustError>()),
      );
    });

    test('another class cannot read it', () async {
      final nonce = newNonce();
      final sealed = await sealReply(
        classKey: classKey,
        signingSeed: seed,
        requestNonce: nonce,
        json: {},
      );
      expect(
        () => openReply(
          classKey: newClassKey(),
          teacherPublicKey: pub,
          requestNonce: nonce,
          sealed: sealed,
        ),
        throwsA(isA<SyncTrustError>()),
      );
    });

    test('a tampered reply is rejected', () async {
      final nonce = newNonce();
      final sealed = await sealReply(
        classKey: classKey,
        signingSeed: seed,
        requestNonce: nonce,
        json: {'x': 'y'},
      );
      final c = sealed['c'] as String;
      sealed['c'] =
          '${c.substring(0, c.length - 2)}${c.endsWith('A') ? 'B' : 'A'}A';
      expect(
        () => openReply(
          classKey: classKey,
          teacherPublicKey: pub,
          requestNonce: nonce,
          sealed: sealed,
        ),
        throwsA(isA<SyncTrustError>()),
      );
    });
  });

  test('request MACs depend on key, path, nonce and body', () async {
    final key = newClassKey();
    final base = await requestMac(
      classKey: key,
      path: 'p',
      nonce: 'n',
      body: 'b',
    );
    expect(
      await requestMac(classKey: key, path: 'p', nonce: 'n', body: 'b'),
      base,
    );
    expect(
      await requestMac(
        classKey: newClassKey(),
        path: 'p',
        nonce: 'n',
        body: 'b',
      ),
      isNot(base),
    );
    expect(
      await requestMac(classKey: key, path: 'q', nonce: 'n', body: 'b'),
      isNot(base),
    );
    expect(
      await requestMac(classKey: key, path: 'p', nonce: 'm', body: 'b'),
      isNot(base),
    );
    expect(
      await requestMac(classKey: key, path: 'p', nonce: 'n', body: 'c'),
      isNot(base),
    );
  });

  group('join codes', () {
    test('codes read cleanly and typing variations normalise', () {
      final code = newJoinCode();
      expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(code, isNot(matches(RegExp('[01IO]'))));
      expect(
        normalizeJoinCode(' ${code.toLowerCase().replaceAll('-', ' ')} '),
        code.replaceAll('-', ''),
      );
      expect(normalizeJoinCode('ABCD-EFG'), isNull);
      expect(normalizeJoinCode('ABCD-EFG0'), isNull); // 0 is never in a code
    });

    test('only the right code proves itself and opens the bundle', () async {
      const code = 'K7M4P9QX';
      final salt = newNonce();
      final secret = await joinSecret(code, salt, rounds: 1000);
      final wrong = await joinSecret('K7M4P9QY', salt, rounds: 1000);
      expect(
        await joinProof(secret, salt),
        isNot(await joinProof(wrong, salt)),
      );

      final bundle = await sealJoinBundle(secret, salt, {'class': 'S2 East'});
      expect(await openJoinBundle(secret, salt, bundle), {'class': 'S2 East'});
      expect(
        () => openJoinBundle(wrong, salt, bundle),
        throwsA(isA<SyncTrustError>()),
      );
    });
  });

  test(
    'channel digest changes when a chunk is removed, not with order',
    () async {
      final a = await channelDigest(['x', 'y', 'z']);
      expect(await channelDigest(['z', 'x', 'y']), a);
      expect(await channelDigest(['x', 'y']), isNot(a));
    },
  );

  test('the full join stretch takes a noticeable but bearable time', () async {
    final watch = Stopwatch()..start();
    await joinSecret('K7M4P9QX', newNonce());
    // Printed, not asserted: timing depends on the machine.
    // ignore: avoid_print
    print('PBKDF2 x$kJoinKdfRounds: ${watch.elapsedMilliseconds} ms');
  });
}
