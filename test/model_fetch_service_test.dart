import 'dart:io';

import 'package:ai_connect_africa/ai_core/model/model_download_service.dart';
import 'package:ai_connect_africa/ai_core/model/model_package.dart';
import 'package:ai_connect_africa/services/model_fetch_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('core fetch is Ready with zero network when both files exist', () async {
    final models = Directory(p.join(tmp.path, 'models'));
    await models.create(recursive: true);
    await File(p.join(models.path, ModelFetchFiles.chat)).writeAsString('ok');
    await File(p.join(models.path, ModelFetchFiles.translate))
        .writeAsString('ok');

    final downloader = _NoNetworkDownloader();
    final svc = _TestFetchService(downloader, models.path);

    expect(await svc.areCorePackagesReady(), isTrue);
    final state = await svc.fetchCorePackages();
    expect(state.isReady, isTrue);
    expect(state.statusLabel, 'Ready');
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

  test('core packages are tutor + translation only', () {
    final ids = ModelFetchService.corePackages.map((p) => p.id).toList();
    expect(ids, ['core_chat', 'core_translate']);
    expect(ids, isNot(contains('coder')));
    expect(ModelFetchService.coderPackage.id, 'coder');
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
