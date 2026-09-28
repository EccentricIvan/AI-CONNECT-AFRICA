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

  group('channel manifests', () {
    Future<ChannelManifest> signed(String seed, {int version = 3}) async =>
        ChannelManifest(
          schoolId: 's',
          classUuid: 'c',
          subjectId: 'chemistry',
          digest: 'd',
          version: version,
          signature: await signManifest(
            signingSeed: seed,
            schoolId: 's',
            classUuid: 'c',
            subjectId: 'chemistry',
            digest: 'd',
            version: version,
          ),
        );

    test('verify with the teacher key, fail with any other', () async {
      final teacher = newSigningSeed();
      final m = await signed(teacher);
      expect(await verifyManifest(m, await signingPublicKey(teacher)), isTrue);
      expect(
        await verifyManifest(m, await signingPublicKey(newSigningSeed())),
        isFalse,
      );
    });

    test('any changed field breaks the signature', () async {
      final teacher = newSigningSeed();
      final pub = await signingPublicKey(teacher);
      final m = await signed(teacher);
      ChannelManifest tweak({
        String? school,
        String? cls,
        String? subject,
        String? digest,
        int? version,
      }) => ChannelManifest(
        schoolId: school ?? m.schoolId,
        classUuid: cls ?? m.classUuid,
        subjectId: subject ?? m.subjectId,
        digest: digest ?? m.digest,
        version: version ?? m.version,
        signature: m.signature,
      );
      for (final bad in [
        tweak(school: 'x'),
        tweak(cls: 'x'),
        tweak(subject: 'x'),
        tweak(digest: 'x'),
        tweak(version: 4),
      ]) {
        expect(await verifyManifest(bad, pub), isFalse);
      }
      expect(
        await verifyManifest(tweak(), pub),
        isTrue,
        reason: 'untouched still verifies',
      );
    });

    test('a garbage signature is a no, not a crash', () async {
      final pub = await signingPublicKey(newSigningSeed());
      const m = ChannelManifest(
        schoolId: 's',
        classUuid: 'c',
        subjectId: 'x',
        digest: 'd',
        version: 1,
        signature: '!!not base64!!',
      );
      expect(await verifyManifest(m, pub), isFalse);
    });
  });

  test('relay replies and reports only open with the class key and nonce',
      () async {
    final key = newClassKey();
    final nonce = newNonce();
    final relay = await sealRelayReply(
      classKey: key,
      requestNonce: nonce,
      json: {'a': 1},
    );
    expect(
      await openRelayReply(classKey: key, requestNonce: nonce, sealed: relay),
      {'a': 1},
    );
    expect(
      () => openRelayReply(
        classKey: newClassKey(),
        requestNonce: nonce,
        sealed: relay,
      ),
      throwsA(isA<SyncTrustError>()),
    );
    expect(
      () => openRelayReply(
        classKey: key,
        requestNonce: newNonce(),
        sealed: relay,
      ),
      throwsA(isA<SyncTrustError>()),
    );
    final report = await sealReport(
      classKey: key,
      requestNonce: nonce,
      json: [1],
    );
    expect(
      await openReport(classKey: key, requestNonce: nonce, sealed: report),
      [1],
    );
    // A report can't be opened as a relay reply or vice versa.
    expect(
      () => openRelayReply(classKey: key, requestNonce: nonce, sealed: report),
      throwsA(isA<SyncTrustError>()),
    );
  });

  test('the full join stretch takes a noticeable but bearable time', () async {
    final watch = Stopwatch()..start();
    await joinSecret('K7M4P9QX', newNonce());
    // Printed, not asserted: timing depends on the machine.
    // ignore: avoid_print
    print('PBKDF2 x$kJoinKdfRounds: ${watch.elapsedMilliseconds} ms');
  });
}
