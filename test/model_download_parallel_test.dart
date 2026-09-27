import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ai_connect_africa/ai_core/model/model_download_service.dart';
import 'package:ai_connect_africa/ai_core/model/model_package.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves [body] over loopback with real `bytes=a-b` Range support, the way
/// the Hugging Face CDN and GitHub release storage do.
class _RangeServer {
  _RangeServer(this.body, {this.rangeAware = true, this.dropFirstRequestFor, this.corrupt = false});

  final Uint8List body;
  final bool rangeAware;

  /// A piece start offset whose first request is cut off mid-way.
  final int? dropFirstRequestFor;
  final bool corrupt;

  late final HttpServer _server;
  int servedBytes = 0;
  int maxConcurrent = 0;
  int _active = 0;
  bool _dropped = false;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      _active++;
      maxConcurrent = max(maxConcurrent, _active);
      try {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        var start = 0, end = body.length - 1;
        final m = range == null ? null : RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
        if (m != null && rangeAware) {
          start = int.parse(m.group(1)!);
          if (m.group(2)!.isNotEmpty) end = min(int.parse(m.group(2)!), body.length - 1);
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${body.length}');
        }
        var slice = Uint8List.sublistView(body, start, end + 1);
        if (corrupt && slice.length > 10) {
          slice = Uint8List.fromList(slice)..[5] ^= 0xff;
        }
        req.response.contentLength = slice.length;
        if (dropFirstRequestFor == start && !_dropped && slice.length > 1) {
          _dropped = true;
          // Send half, then kill the connection.
          req.response.add(Uint8List.sublistView(slice, 0, slice.length ~/ 2));
          await req.response.flush();
          final socket = await req.response.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        }
        // Stream in small writes so pieces overlap in time.
        for (var i = 0; i < slice.length; i += 16 * 1024) {
          req.response.add(Uint8List.sublistView(slice, i, min(i + 16 * 1024, slice.length)));
          servedBytes += min(16 * 1024, slice.length - i);
          await req.response.flush();
        }
        await req.response.close();
      } catch (_) {
        // Client went away (e.g. a probe cancelling its body).
      } finally {
        _active--;
      }
    });
    return 'http://${_server.address.address}:${_server.port}/model.bin';
  }

  Future<void> stop() => _server.close(force: true);
}

ModelPackage _pkg(String url, Uint8List body) => ModelPackage(
      id: 'chat',
      label: 'Tutor model',
      fileName: 'model.bin',
      url: url,
      sha256: sha256.convert(body).toString(),
      approxBytes: body.length,
      essential: true,
    );

ModelDownloadService _service() => ModelDownloadService(
      connections: 4,
      chunkBytes: 256 * 1024,
      parallelMinBytes: 1024 * 1024,
      stallTimeout: const Duration(seconds: 2),
    );

void main() {
  late Directory tmp;
  final body = Uint8List.fromList(List.generate(3 * 1024 * 1024 + 12345, (i) => (i * 31 + i ~/ 7) & 0xff));

  setUp(() async => tmp = await Directory.systemTemp.createTemp('model_dl_par'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('a large file comes down over several connections at once, intact', () async {
    final server = _RangeServer(body);
    final url = await server.start();
    addTearDown(server.stop);
    final target = '${tmp.path}/model.bin';
    final states = <ModelDownloadState>[];

    await _service().download(_pkg(url, body), targetPath: target, onState: states.add);

    expect(await File(target).readAsBytes(), body);
    expect(server.maxConcurrent, greaterThan(1), reason: 'pieces must be fetched in parallel');
    expect(await File('$target.part').exists(), isFalse);
    expect(await File('$target.part.chunks').exists(), isFalse);
    expect(states.last.phase, DownloadPhase.done);
    // Throttled: far fewer reports than the ~200 network writes.
    expect(states.length, lessThan(60), reason: '${states.length} progress reports');
  });

  test('a cancelled download resumes, fetching only the missing pieces', () async {
    final server = _RangeServer(body);
    final url = await server.start();
    addTearDown(server.stop);
    final target = '${tmp.path}/model.bin';

    final token = CancellationToken();
    await expectLater(
      ModelDownloadService(
        connections: 4,
        chunkBytes: 256 * 1024,
        parallelMinBytes: 1024 * 1024,
        progressInterval: Duration.zero,
      ).download(
        _pkg(url, body),
        targetPath: target,
        cancelToken: token,
        onState: (s) {
          if (s.receivedBytes > body.length ~/ 2) token.cancel();
        },
      ),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(await File('$target.part.chunks').exists(), isTrue, reason: 'progress is kept');

    final servedFirst = server.servedBytes;
    await _service().download(_pkg(url, body), targetPath: target);
    expect(await File(target).readAsBytes(), body);
    expect(server.servedBytes - servedFirst, lessThan(body.length),
        reason: 'finished pieces are not fetched again');
  });

  test('a dropped connection only re-fetches that piece', () async {
    final server = _RangeServer(body, dropFirstRequestFor: 256 * 1024);
    final url = await server.start();
    addTearDown(server.stop);
    final target = '${tmp.path}/model.bin';

    await _service().download(_pkg(url, body), targetPath: target);
    expect(await File(target).readAsBytes(), body);
  });

  test('a server that ignores Range still works, one connection', () async {
    final server = _RangeServer(body, rangeAware: false);
    final url = await server.start();
    addTearDown(server.stop);
    final target = '${tmp.path}/model.bin';

    await _service().download(_pkg(url, body), targetPath: target);
    expect(await File(target).readAsBytes(), body);
    expect(server.maxConcurrent, lessThanOrEqualTo(2)); // the probe, then one stream
  });

  test('corrupted bytes fail the check and leave nothing to resume onto', () async {
    final server = _RangeServer(body, corrupt: true);
    final url = await server.start();
    addTearDown(server.stop);
    final target = '${tmp.path}/model.bin';

    await expectLater(
      _service().download(_pkg(url, body), targetPath: target),
      throwsA(isA<ModelDownloadException>().having((e) => e.message, 'message', contains('integrity'))),
    );
    expect(await File(target).exists(), isFalse);
    expect(await File('$target.part').exists(), isFalse);
    expect(await File('$target.part.chunks').exists(), isFalse);
  });
}
