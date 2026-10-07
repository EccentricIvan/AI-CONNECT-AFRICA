import 'dart:io';

import 'package:ai_connect_africa/ai_core/model/model_manifest.dart';
import 'package:ai_connect_africa/ai_core/model/model_verifier.dart';
import 'package:ai_connect_africa/ai_core/translate/supported_languages.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const registry = ModelRegistry();

  test('models are found by what they can do, on the runtime asked for', () {
    expect(
      registry.forCapability(
        ModelCapability.code,
        runtime: ModelRuntime.llamaCpp,
      ),
      [kBrainGguf],
    );
    expect(
      registry.forCapability(
        ModelCapability.translate,
        runtime: ModelRuntime.liteRtLm,
        language: 'lg',
      ),
      [kTranslatorLiteRt],
    );
    expect(
      registry.forCapability(
        ModelCapability.translate,
        runtime: ModelRuntime.llamaCpp,
        language: 'fr',
      ),
      isEmpty,
    );
    expect(
      registry.forFile('/x/models/AFRISLM-0.8B-Q4_K_M.gguf'),
      kTranslatorGguf,
    );
    expect(registry.forFile('/x/models/qwen_coder_1.5b.Q4_K_M.gguf'), isNull);
  });

  test('the translator manifest lists every language the app offers', () {
    expect(kTranslatorGguf.languages.toSet(), {
      for (final l in supportedLanguages) l.code,
    });
  });

  group('verifier', () {
    late Directory dir;
    late File file;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('model_verify');
      file = File(p.join(dir.path, 'brain.gguf'));
      await file.writeAsString('model bytes');
    });
    tearDown(() => dir.delete(recursive: true));

    ModelVerifier verifierFor(String hash) => ModelVerifier(
      registry: ModelRegistry([
        ModelManifest(
          id: 'test',
          version: '1',
          fileName: 'brain.gguf',
          runtime: ModelRuntime.llamaCpp,
          quantization: 'q4',
          capabilities: const {ModelCapability.chat},
          sha256: hash,
          approxBytes: 11,
          license: 'Apache-2.0',
        ),
      ]),
    );

    test('a file matching its release is verified and remembered', () async {
      final good = sha256.convert('model bytes'.codeUnits).toString();
      final v = verifierFor(good);
      expect(await v.cached(file.path), isNull);
      expect(await v.verify(file.path), ModelVerification.verified);
      expect(await v.cached(file.path), ModelVerification.verified);
      expect(await v.isKnownBad(file.path), isFalse);
    });

    test('a swapped file is known bad until it changes again', () async {
      final v = verifierFor('0' * 64);
      expect(await v.verify(file.path), ModelVerification.mismatch);
      expect(await v.isKnownBad(file.path), isTrue);
      await file.writeAsString('other bytes, other size');
      expect(await v.cached(file.path), isNull);
    });

    test('a file with no manifest is unknown, never refused', () async {
      final other = File(p.join(dir.path, 'other.gguf'));
      await other.writeAsString('x');
      final v = verifierFor('0' * 64);
      expect(await v.verify(other.path), ModelVerification.unknown);
      expect(await v.isKnownBad(other.path), isFalse);
    });
  });
}
