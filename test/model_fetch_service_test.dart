import 'dart:io';

import 'package:ai_connect_africa/ai_core/model/model_download_service.dart';
import 'package:ai_connect_africa/ai_core/model/model_package.dart';
import 'package:ai_connect_africa/services/model_fetch_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ai_connect_africa/ai_core/model/device_tier.dart';

class _NoNetworkDownloader extends ModelDownloadService {
  int calls = 0;

  @override
  Future<String> download(
    ModelPackage pkg, {
    required String targetPath,
    void Function(ModelDownloadState state)? onState,
    CancellationToken? cancelToken,
  }) async {
    calls++;
    throw const ModelDownloadException('network should not be hit');
  }
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('model_fetch_');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('core fetch is Ready with zero network when all files exist', () async {
    final models = Directory(p.join(tmp.path, 'models'));
    await models.create(recursive: true);
    await File(p.join(models.path, ModelFetchFiles.chat)).writeAsString('ok');
    await File(p.join(models.path, ModelFetchFiles.translate))
        .writeAsString('ok');
    await File(p.join(models.path, ModelFetchFiles.coder)).writeAsString('ok');

    final downloader = _NoNetworkDownloader();
    final svc = _TestFetchService(downloader, models.path);

    expect(await svc.areAllPackagesReady(), isTrue);
    final state = await svc.fetchAllPackages();
    expect(state.isReady, isTrue);
    expect(state.statusLabel, 'Ready');
    expect(state.coderReady, isTrue);
    expect(downloader.calls, 0);
  });

  test('coder fetch skips network when file already present', () async {
    final models = Directory(p.join(tmp.path, 'models'));
    await models.create(recursive: true);
    await File(p.join(models.path, ModelFetchFiles.coder)).writeAsString('ok');

    final downloader = _NoNetworkDownloader();
    final svc = _TestFetchService(downloader, models.path);

    expect(await svc.isCoderReady(), isTrue);
    final state = await svc.fetchCoderPackage();
    expect(state.coderReady, isTrue);
    expect(downloader.calls, 0);
  });

  test('white-label labels never expose model brand tokens', () {
    for (final f in [0.0, 0.2, 0.5, 0.9, 1.0]) {
      final label = ModelFetchService.whiteLabelStatus(f, connecting: f == 0);
      expect(label.toLowerCase(), isNot(contains('gguf')));
      expect(label.toLowerCase(), isNot(contains('qwen')));
      expect(label.toLowerCase(), isNot(contains('afrislm')));
      expect(label.toLowerCase(), isNot(contains('litert')));
    }
  });

  test('Install Packages is the brain and the translator — nothing else', () {
    final ids = ModelFetchService.allPackages.map((p) => p.id).toList();
    expect(ids, ['core_chat', 'core_translate']);
    // The coder IS the brain: one file, downloaded once.
    expect(ModelFetchService.coderPackage.fileName,
        ModelFetchService.coreChatPackage.fileName);
    final files = ModelFetchService.allPackages.map((p) => p.fileName);
    expect(files.toSet(), hasLength(files.length),
        reason: 'no file may be queued twice');
  });

  test('Windows downloads the GGUFs, Android the LiteRT builds, each pinned', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(ModelFetchFiles.chat, 'qwen2.5-coder-1.5b-instruct.gguf');
    expect(ModelFetchService.coreChatPackage.url,
        '$kModelFetchHfBaseUrl/qwen2.5-coder-1.5b-instruct.gguf');
    expect(ModelFetchService.coreTranslatePackage.url,
        '$kModelFetchHfBaseUrl/afrislm-0.8b-q4_k_m.gguf');
    expect(ModelFetchService.coreChatPackage.sha256, hasLength(64));
    expect(ModelFetchService.coreChatPackage.mirrors, isEmpty);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(ModelFetchFiles.chat, 'qwen2.5-coder-1.5b-instruct_int4.litertlm');
    expect(ModelFetchService.coreChatPackage.url,
        '$kModelFetchHfBaseUrl/qwen2.5-coder-1.5b-instruct_int4.litertlm');
    // Translator build follows the memory tier: int8 above ~5 GB, int4 on
    // 4 GB phones (with int8 as the fallback download).
    DeviceTier.overrideForTesting(DeviceTier.fromMeminfo('MemTotal: 7812344 kB'));
    expect(ModelFetchService.coreTranslatePackage.url,
        '$kModelFetchHfBaseUrl/afrislm-0.8b_int8.litertlm');
    expect(ModelFetchFiles.translateFallback, isNull);
    DeviceTier.overrideForTesting(DeviceTier.fromMeminfo('MemTotal: 3812344 kB'));
    expect(ModelFetchService.coreTranslatePackage.url,
        '$kModelFetchHfBaseUrl/afrislm-0.8b_int8.litertlm');
    expect(ModelFetchService.coreTranslatePackage.sha256, hasLength(64));
    DeviceTier.overrideForTesting(null);
    expect(ModelFetchService.coreChatPackage.sha256, hasLength(64));
    // While the Oticgroup repo is being filled, the same files come from the
    // conversion workflow's GitHub release (and litert-community for the
    // brain) — the SHA-256 pin makes every mirror equally safe.
    expect(ModelFetchService.coreChatPackage.mirrors,
        everyElement(endsWith('.litertlm')));
    expect(ModelFetchService.coreTranslatePackage.mirrors, isNotEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  test('downloads land in canonical install directory', () async {
    final svc = ModelFetchService(downloader: _NoNetworkDownloader());
    final chatPath = await svc.pathFor(ModelFetchFiles.chat);
    final translatePath = await svc.pathFor(ModelFetchFiles.translate);
    expect(chatPath, endsWith(ModelFetchFiles.chat));
    expect(translatePath, endsWith(ModelFetchFiles.translate));
    // Desktop → …/OTIC/<file>; Android → …/models/<file>
    expect(
      chatPath.contains('${Platform.pathSeparator}OTIC${Platform.pathSeparator}') ||
          chatPath.contains(
            '${Platform.pathSeparator}models${Platform.pathSeparator}',
          ),
      isTrue,
    );
  });

  test('checkPackagesCached requires the brain and the translator', () async {
    final models = Directory(p.join(tmp.path, 'models'));
    await models.create(recursive: true);
    await File(p.join(models.path, ModelFetchFiles.translate))
        .writeAsString('ok');

    final svc = _TestFetchService(_NoNetworkDownloader(), models.path);
    expect(await svc.checkPackagesCached(), isFalse);

    await File(p.join(models.path, ModelFetchFiles.chat)).writeAsString('ok');
    expect(await svc.checkPackagesCached(), isTrue);
    expect(await svc.isCoderReady(), isTrue,
        reason: 'coding runs on the brain');
  });

  test('fetchMissingPackages streams white-label progress only', () async {
    final models = Directory(p.join(tmp.path, 'models'));
    await models.create(recursive: true);
    await File(p.join(models.path, ModelFetchFiles.chat)).writeAsString('ok');
    await File(p.join(models.path, ModelFetchFiles.translate))
        .writeAsString('ok');
    await File(p.join(models.path, ModelFetchFiles.coder)).writeAsString('ok');

    final svc = _TestFetchService(_NoNetworkDownloader(), models.path);
    final labels = <String>[];
    await for (final s in svc.fetchMissingPackages()) {
      labels.add(s.statusLabel);
      expect(s.statusLabel.toLowerCase(), isNot(contains('gguf')));
      expect(s.statusLabel.toLowerCase(), isNot(contains('qwen')));
    }
    expect(labels, isNotEmpty);
    expect(labels.last, 'Ready');
  });
}

class _TestFetchService extends ModelFetchService {
  _TestFetchService(ModelDownloadService downloader, this._modelsPath)
      : super(downloader: downloader);

  final String _modelsPath;

  @override
  Future<Directory> modelsDirectory({bool ensure = true}) async {
    final d = Directory(_modelsPath);
    if (ensure) await d.create(recursive: true);
    return d;
  }

  @override
  Future<bool> isPackagePresent(ModelPackage pkg) async {
    // Size floor is enforced in production downloads; presence-only here.
    return File(p.join(_modelsPath, pkg.fileName)).existsSync();
  }
}
