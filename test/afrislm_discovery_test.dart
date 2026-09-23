import 'dart:io';

import 'package:ai_connect_africa/ai_core/model/model_locations.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:ai_connect_africa/services/model_fetch_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _ensureGgufMagic(File fixture) async {
  final raf = await fixture.open();
  try {
    final header = await raf.read(4);
    if (header.length >= 4 &&
        header[0] == 0x47 &&
        header[1] == 0x47 &&
        header[2] == 0x55 &&
        header[3] == 0x46) {
      return;
    }
    await raf.setPosition(0);
    await raf.writeFrom(const [0x47, 0x47, 0x55, 0x46]);
  } finally {
    await raf.close();
  }
}

Future<void> _writeGgufStub(File fixture, int bytes) async {
  await fixture.parent.create(recursive: true);
  final raf = await fixture.open(mode: FileMode.write);
  await raf.writeFrom(const [0x47, 0x47, 0x55, 0x46]);
  await raf.truncate(bytes);
  await raf.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixtureBytes = 320 * 1024 * 1024;

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Install Packages Q4 name is the AfriSLM canonical file', () {
    expect(
      AfriSlmModelManager.modelFileName,
      ModelFetchFiles.translate,
    );
    expect(
      AfriSlmModelManager.allFileNames,
      contains('translate-afrislm.gguf'),
    );
  });

  test('candidate list includes Documents/OTIC and repo models/', () async {
    const name = 'afrislm-0.8b-q4_k_m.gguf';
    final files = await modelCandidateFiles(name);
    expect(
      files.any((f) => f.contains('Documents') && f.contains('OTIC')),
      isTrue,
    );
    expect(files.any((f) => f.contains('${p.separator}models${p.separator}')), isTrue);
  });

  test('AfriSLM manager finds the Q4 GGUF in repo models/', () async {
    final fixture = File(
      p.join(Directory.current.path, 'models', 'afrislm-0.8b-q4_k_m.gguf'),
    );
    final hadFixture = await fixture.exists();
    if (!hadFixture) {
      await _writeGgufStub(fixture, fixtureBytes);
      addTearDown(() async {
        if (await fixture.exists()) await fixture.delete();
      });
    } else {
      await _ensureGgufMagic(fixture);
    }

    final info = await AfriSlmModelManager().checkModel();
    expect(
      info.isReady,
      isTrue,
      reason: 'looked for ${AfriSlmModelManager.modelFileName} + '
          '${AfriSlmModelManager.alternateFileNames} — '
          'got ${info.status} at ${info.path}',
    );
    expect(info.sizeBytes, greaterThan(300 * 1024 * 1024));
    expect(File(info.path!).existsSync(), isTrue);
  });

  test('AfriSLM manager finds Windows-zip translate-afrislm.gguf alias', () async {
    final q4 = File(
      p.join(Directory.current.path, 'models', 'afrislm-0.8b-q4_k_m.gguf'),
    );
    final alias = File(
      p.join(Directory.current.path, 'models', 'translate-afrislm.gguf'),
    );
    final hadQ4 = await q4.exists();
    final hadAlias = await alias.exists();
    if (hadQ4 || hadAlias) {
      final info = await AfriSlmModelManager().checkModel();
      expect(info.isReady, isTrue);
      return;
    }
    await _writeGgufStub(alias, fixtureBytes);
    addTearDown(() async {
      if (await alias.exists()) await alias.delete();
    });
    final info = await AfriSlmModelManager().checkModel();
    expect(info.isReady, isTrue, reason: '${info.status} ${info.path}');
    expect(info.path, contains('translate-afrislm.gguf'));
  });

  test('the brain manager finds the coder GGUF, not AfriSLM', () async {
    final fixture = File(
      p.join(Directory.current.path, 'models', ModelManager.brainGgufFileName),
    );
    final hadFixture = await fixture.exists();
    if (!hadFixture) {
      // Above the brain's 400 MB truncation floor.
      await _writeGgufStub(fixture, 420 * 1024 * 1024);
      addTearDown(() async {
        if (await fixture.exists()) await fixture.delete();
      });
    }

    final info = await ModelManager().checkModel();
    expect(info.isReady, isTrue, reason: '${info.status} ${info.path}');
    expect(info.path!.toLowerCase(), contains('coder-1.5b'));
    expect(info.path!.toLowerCase().contains('afrislm'), isFalse);
  });
}
