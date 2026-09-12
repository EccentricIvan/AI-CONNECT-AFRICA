import 'dart:io';

import 'package:ai_connect_africa/ai_core/model/model_locations.dart';
import 'package:ai_connect_africa/ai_core/model/model_manager.dart';
import 'package:ai_connect_africa/ai_core/translate/afrislm_model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixtureBytes = 320 * 1024 * 1024;

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
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
      await fixture.parent.create(recursive: true);
      final raf = await fixture.open(mode: FileMode.write);
      await raf.truncate(fixtureBytes);
      await raf.close();
      addTearDown(() async {
        if (await fixture.exists()) await fixture.delete();
      });
    }

    final info = await AfriSlmModelManager().checkModel();
    expect(
      info.isReady,
      isTrue,
      reason: 'looked for ${AfriSlmModelManager.alternateFileNames} — '
          'got ${info.status} at ${info.path}',
    );
    expect(info.sizeBytes, greaterThan(300 * 1024 * 1024));
    expect(File(info.path!).existsSync(), isTrue);
  });

  test('Qwen manager finds the 0.6B GGUF brain, not AfriSLM', () async {
    final fixture = File(
      p.join(Directory.current.path, 'models', 'qwen-0.6b-instruct.gguf'),
    );
    final hadFixture = await fixture.exists();
    if (!hadFixture) {
      await fixture.parent.create(recursive: true);
      final raf = await fixture.open(mode: FileMode.write);
      await raf.truncate(fixtureBytes);
      await raf.close();
      addTearDown(() async {
        if (await fixture.exists()) await fixture.delete();
      });
    }

    final info = await ModelManager().checkModel();
    expect(info.isReady, isTrue, reason: '${info.status} ${info.path}');
    expect(info.path!.toLowerCase(), contains('qwen-0.6b-instruct.gguf'));
    expect(info.path!.toLowerCase().contains('afrislm'), isFalse);
    expect(info.path!.toLowerCase().contains('1.5b'), isFalse);
  });
}
