import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'model_package.dart';

/// Where a download currently is, for the progress UI.
enum DownloadPhase { idle, connecting, downloading, verifying, done, failed }

@immutable
class ModelDownloadState {
  const ModelDownloadState({
    this.phase = DownloadPhase.idle,
    this.receivedBytes = 0,
    this.totalBytes,
    this.error,
  });

  final DownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;
  final String? error;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  bool get isActive =>
      phase == DownloadPhase.connecting ||
      phase == DownloadPhase.downloading ||
      phase == DownloadPhase.verifying;

  ModelDownloadState copyWith({
    DownloadPhase? phase,
    int? receivedBytes,
    int? totalBytes,
    String? error,
  }) =>
      ModelDownloadState(
        phase: phase ?? this.phase,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        error: error,
      );
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lets the UI stop a download without tearing down the service.
class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Fetches a [ModelPackage] (the brain or the translator, from the Hugging
/// Face repo in `kModelFetchHfBaseUrl`) to local storage.
///
/// Three things make this different from a plain GET, and all three exist
/// because the target device is a low-end phone on an expensive, unreliable
/// connection pulling up to ~1.1 GB:
///
/// 1. **Resume.** A dropped connection continues from the byte it reached
///    using an HTTP Range request instead of restarting. GitHub redirects
///    release assets to objects.githubusercontent.com, which answers 206 and
///    advertises `Accept-Ranges: bytes`, so the range survives the redirect.
/// 2. **Streamed SHA-256.** The digest is computed chunk by chunk while the
///    bytes are written, so verification costs no second pass over 642 MB and
///    no extra memory.
/// 3. **`.part` then rename.** A killed download must never leave a truncated
///    file at a path model discovery would find, which
///    fails in confusing ways rather than obvious ones.
///
/// **Speed.** A large file is fetched in [chunkBytes] pieces over
/// [connections] parallel HTTP Range requests. A single TCP connection on a
/// high-latency mobile link tops out far below the link's real capacity; a
/// few in parallel fill it. Finished pieces are recorded in a
/// `<target>.part.chunks` file, so a resume only fetches the missing ones.
/// Progress is reported at most every [progressInterval] (not per network
/// packet), and the SHA-256 check runs in a background isolate. A server
/// that ignores Range falls back to the single-stream path.
class ModelDownloadService {
  ModelDownloadService({
    HttpClient? client,
    this.connections = 4,
    this.chunkBytes = 8 * 1024 * 1024,
    this.parallelMinBytes = 32 * 1024 * 1024,
    this.progressInterval = const Duration(milliseconds: 200),
    this.stallTimeout = const Duration(seconds: 45),
    // ignore: prefer_initializing_formals
  }) : _client = client;

  /// A connection that delivers no bytes for this long is abandoned and
  /// retried. Mobile links often stall without closing, which would
  /// otherwise hang the download for good.
  final Duration stallTimeout;

  /// Injected only by tests; production builds create a client per download.
  final HttpClient? _client;

  /// Parallel connections for a large file. 1 disables parallel fetching.
  final int connections;

  /// Size of each parallel piece — also the resume granularity.
  final int chunkBytes;

  /// Files smaller than this use one connection.
  final int parallelMinBytes;

  /// Minimum gap between progress reports while bytes are flowing.
  final Duration progressInterval;

  static const _maxAttempts = 3;

  /// Retries per piece before the whole download reports a network error.
  static const _chunkAttempts = 4;

  HttpClient _createClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 45)
    ..idleTimeout = const Duration(minutes: 10)
    ..autoUncompress = true
    ..userAgent = 'AI-Connect-Africa/1.0 (Windows+Android classroom installer)';

  /// Downloads [pkg] to [targetPath], reporting progress through [onState].
  ///
  /// Resumes from an existing `.part` file when one is present. Retries
  /// transient network failures (Hugging Face CDN redirects + flaky school
  /// Wi‑Fi) without discarding the partial file. Returns the final path on
  /// success; throws [ModelDownloadException] otherwise.
  Future<String> download(
    ModelPackage pkg, {
    required String targetPath,
    void Function(ModelDownloadState state)? onState,
    CancellationToken? cancelToken,
  }) async {
    // Main URL first, then each mirror when a URL is missing or refused
    // (404/401/403). The .part file carries over between mirrors: the
    // SHA-256 check at the end proves the bytes are the same file.
    final urls = [pkg.url, ...pkg.mirrors];
    ModelDownloadException? lastHardFailure;
    for (final url in urls) {
      try {
        return await _downloadFrom(
          pkg.copyWithUrl(url),
          targetPath: targetPath,
          onState: onState,
          cancelToken: cancelToken,
        );
      } on ModelDownloadException catch (e) {
        final msg = e.message.toLowerCase();
        final tryNext = msg.contains('http 404') ||
            msg.contains('http 401') ||
            msg.contains('http 403');
        if (!tryNext || url == urls.last) rethrow;
        lastHardFailure = e;
        debugPrint('ModelDownloadService: $url refused (${e.message}); trying next mirror');
      }
    }
    throw lastHardFailure ??
        const ModelDownloadException('No download location for this package.');
  }

  Future<String> _downloadFrom(
    ModelPackage pkg, {
    required String targetPath,
    void Function(ModelDownloadState state)? onState,
    CancellationToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const ModelDownloadException('Download cancelled.');
      }
      try {
        return await _downloadOnce(
          pkg,
          targetPath: targetPath,
          onState: onState,
          cancelToken: cancelToken,
        );
      } on ModelDownloadException catch (e) {
        lastError = e;
        // Cancel / integrity / storage / hard HTTP errors must not retry.
        final msg = e.message.toLowerCase();
        final fatal = msg.contains('cancelled') ||
            msg.contains('integrity') ||
            msg.contains('incomplete') ||
            msg.contains('not enough storage') ||
            msg.contains('http 404') ||
            msg.contains('http 401') ||
            msg.contains('http 403');
        if (fatal || attempt >= _maxAttempts) rethrow;
        debugPrint(
          'ModelDownloadService: attempt $attempt failed (${e.message}); '
          'retrying…',
        );
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      } on SocketException catch (e) {
        lastError = e;
        if (attempt >= _maxAttempts) {
          final msg = 'Network error: ${e.message}. The download resumes where '
              'it stopped when you try again.';
          onState?.call(ModelDownloadState(
            phase: DownloadPhase.failed,
            error: msg,
          ));
          throw ModelDownloadException(msg);
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw ModelDownloadException(
      lastError?.toString() ?? 'Download failed after $_maxAttempts attempts.',
    );
  }

  Future<String> _downloadOnce(
    ModelPackage pkg, {
    required String targetPath,
    void Function(ModelDownloadState state)? onState,
    CancellationToken? cancelToken,
  }) async {
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final partial = File('$targetPath.part');

    var state = const ModelDownloadState(phase: DownloadPhase.connecting);
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    void emit(ModelDownloadState next) {
      state = next;
      lastEmit = DateTime.now();
      onState?.call(next);
    }

    // Progress while bytes flow: a report per packet (tens of thousands per
    // file) rebuilds the install screen on the thread reading the socket.
    void emitProgress(ModelDownloadState next) {
      state = next;
      if (DateTime.now().difference(lastEmit) >= progressInterval) emit(next);
    }

    emit(state);

    var resumeFrom = 0;
    if (await partial.exists()) {
      resumeFrom = await partial.length();
    }

    final ownsClient = _client == null;
    final client = _client ?? _createClient();

    // A large file on a server that honours Range goes the parallel way.
    if (connections > 1 && pkg.approxBytes >= parallelMinBytes) {
      int? total;
      try {
        total = await _probeRangeSupport(client, pkg);
      } on ModelDownloadException catch (e) {
        emit(state.copyWith(phase: DownloadPhase.failed, error: e.message));
        if (ownsClient) client.close(force: true);
        rethrow; // a hard HTTP error: let the caller try the next mirror
      } catch (e) {
        // Probe trouble (odd server, dropped connection): the single-stream
        // path below still works, just slower.
        debugPrint('ModelDownloadService: parallel fetch unavailable ($e)');
      }

      if (total != null && total >= parallelMinBytes) {
        // Committed to pieces from here: any failure keeps the finished ones
        // for the next resume rather than falling back and discarding them.
        try {
          await _ensureSpaceFor(pkg, targetPath, alreadyHave: 0);
          return await _downloadParallel(
            client,
            pkg,
            total: total,
            targetPath: targetPath,
            emit: emit,
            emitProgress: emitProgress,
            cancelToken: cancelToken,
          );
        } on ModelDownloadException catch (e) {
          emit(state.copyWith(phase: DownloadPhase.failed, error: e.message));
          rethrow;
        } on FileSystemException {
          const msg = 'Could not save the package. The device may be out of storage.';
          emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
          throw const ModelDownloadException(msg);
        } catch (e) {
          final msg = 'Network error: $e. The download resumes where it stopped '
              'when you try again.';
          emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
          throw ModelDownloadException(msg);
        } finally {
          if (ownsClient) client.close(force: true);
        }
      }

      // Range isn't honoured: a sidecar from an earlier parallel attempt is
      // useless to the single stream, and its .part isn't a contiguous prefix.
      final sidecar = File('$targetPath.part.chunks');
      if (await sidecar.exists()) {
        await sidecar.delete();
        if (await partial.exists()) await partial.delete();
        resumeFrom = 0;
      }
    }

    await _ensureSpaceFor(pkg, targetPath, alreadyHave: resumeFrom);

    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(pkg.url));
      request.followRedirects = true;
      request.maxRedirects = 12;
      if (resumeFrom > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
      }
      final response = await request.close();

      // 206 means the resume took. A 200 in reply to a Range request means
      // the server ignored it and is sending the whole file, so the bytes
      // already on disk have to be thrown away rather than appended to.
      final resumed = response.statusCode == HttpStatus.partialContent;
      if (resumeFrom > 0 && !resumed) {
        resumeFrom = 0;
        if (await partial.exists()) await partial.delete();
      }
      if (response.statusCode != HttpStatus.ok && !resumed) {
        // 5xx → let outer retry keep the .part; 4xx → fatal via message.
        throw ModelDownloadException(_httpMessage(response.statusCode, pkg));
      }

      final contentLength =
          response.contentLength > 0 ? response.contentLength : null;
      final total = contentLength == null ? null : contentLength + resumeFrom;

      // The digest has to cover the whole file, so a resumed download replays
      // the bytes already on disk through the hash before appending new ones.
      final digest = _Sha256Accumulator();
      if (resumeFrom > 0) {
        await for (final chunk in partial.openRead()) {
          digest.add(chunk);
        }
      }

      sink = partial.openWrite(
        mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
      );

      var received = resumeFrom;
      emit(ModelDownloadState(
        phase: DownloadPhase.downloading,
        receivedBytes: received,
        totalBytes: total,
      ));

      await for (final chunk in response.timeout(stallTimeout)) {
        if (cancelToken?.isCancelled ?? false) {
          // Cancelling is not discarding: the .part stays so the next
          // attempt resumes from here instead of re-spending the data.
          throw const ModelDownloadException('Download cancelled.');
        }
        sink.add(chunk);
        digest.add(chunk);
        received += chunk.length;
        emitProgress(state.copyWith(
          phase: DownloadPhase.downloading,
          receivedBytes: received,
          totalBytes: total,
        ));
      }

      await sink.flush();
      await sink.close();
      sink = null;

      emit(state.copyWith(phase: DownloadPhase.verifying));

      final digestHex = digest.close().toString();
      if (pkg.sha256.isNotEmpty && digestHex != pkg.sha256) {
        // Wrong bytes are worse than no bytes: keeping them would make every
        // later retry resume onto a corrupt prefix.
        await partial.delete();
        throw const ModelDownloadException(
          'The downloaded file failed its integrity check and was removed. '
          'This usually means the download was corrupted — try again.',
        );
      }

      final minBytes = (pkg.approxBytes * 0.5).floor();
      if (received < minBytes) {
        await partial.delete();
        throw const ModelDownloadException(
          'The downloaded package looks incomplete and was removed. Try again.',
        );
      }

      if (await target.exists()) await target.delete();
      await partial.rename(targetPath);

      emit(ModelDownloadState(
        phase: DownloadPhase.done,
        receivedBytes: received,
        totalBytes: total,
      ));
      return targetPath;
    } on ModelDownloadException catch (e) {
      emit(state.copyWith(phase: DownloadPhase.failed, error: e.message));
      rethrow;
    } on SocketException catch (e) {
      final msg = 'Network error: ${e.message}. The download resumes where '
          'it stopped when you try again.';
      emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
      throw ModelDownloadException(msg);
    } on HttpException catch (e) {
      final msg = 'Network error: ${e.message}. The download resumes where '
          'it stopped when you try again.';
      emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
      throw ModelDownloadException(msg);
    } on TimeoutException {
      // A stalled connection: the retry loop resumes from the .part.
      const msg = 'Network error: the connection stalled. The download resumes '
          'where it stopped when you try again.';
      emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
      throw const ModelDownloadException(msg);
    } on FileSystemException {
      const msg = 'Could not save the package. The device may be out of storage.';
      emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
      throw const ModelDownloadException(msg);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (ownsClient) client.close(force: true);
    }
  }

  // ── Parallel ranged download ─────────────────────────────────────────────

  /// The file's size when the server answers a one-byte Range request with
  /// 206 — i.e. it can serve pieces in parallel. Null when it can't. Throws
  /// [ModelDownloadException] on a hard HTTP error so mirrors are tried.
  Future<int?> _probeRangeSupport(HttpClient client, ModelPackage pkg) async {
    final request = await client.getUrl(Uri.parse(pkg.url));
    request.followRedirects = true;
    request.maxRedirects = 12;
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final response = await request.close();
    // Only the headers are needed; drop the body (or the whole file, from a
    // server that ignored Range) without reading it.
    unawaited(response.listen(null).cancel());
    final status = response.statusCode;
    if (status == HttpStatus.notFound ||
        status == HttpStatus.unauthorized ||
        status == HttpStatus.forbidden) {
      throw ModelDownloadException(_httpMessage(status, pkg));
    }
    if (status != HttpStatus.partialContent) return null;
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    final total = range == null ? null : RegExp(r'/(\d+)\s*$').firstMatch(range)?.group(1);
    return total == null ? null : int.tryParse(total);
  }

  Future<String> _downloadParallel(
    HttpClient client,
    ModelPackage pkg, {
    required int total,
    required String targetPath,
    required void Function(ModelDownloadState) emit,
    required void Function(ModelDownloadState) emitProgress,
    CancellationToken? cancelToken,
  }) async {
    final partial = File('$targetPath.part');
    final sidecar = File('$targetPath.part.chunks');
    final chunkCount = (total + chunkBytes - 1) ~/ chunkBytes;
    int chunkStart(int i) => i * chunkBytes;
    int chunkEnd(int i) => (i + 1) * chunkBytes > total ? total : (i + 1) * chunkBytes;

    // What is already on disk: pieces listed in the sidecar, or — for a
    // .part left by the single-stream path — every piece inside its prefix.
    final done = <int>{};
    final header = '$total $chunkBytes';
    if (await partial.exists()) {
      if (await sidecar.exists()) {
        final lines = await sidecar.readAsLines();
        if (lines.isNotEmpty && lines.first.trim() == header) {
          for (final l in lines.skip(1)) {
            final i = int.tryParse(l.trim());
            if (i != null && i >= 0 && i < chunkCount) done.add(i);
          }
        }
      } else {
        final prefix = await partial.length();
        for (var i = 0; i < chunkCount && chunkEnd(i) <= prefix; i++) {
          done.add(i);
        }
      }
    }
    if (done.isEmpty && await partial.exists()) await partial.delete();
    await sidecar.writeAsString('$header\n${done.map((i) => '$i\n').join()}');

    final raf = await partial.open(mode: FileMode.append);
    // One file handle, writes serialised: pieces from different connections
    // must never interleave a seek and a write.
    var writeLock = Future<void>.value();
    Future<void> locked(Future<void> Function() body) {
      final next = writeLock.then((_) => body());
      writeLock = next.catchError((_) {});
      return next;
    }

    try {
      if (await raf.length() < total) await raf.truncate(total);

      var received = 0;
      for (final i in done) {
        received += chunkEnd(i) - chunkStart(i);
      }
      emit(ModelDownloadState(
        phase: DownloadPhase.downloading,
        receivedBytes: received,
        totalBytes: total,
      ));

      final queue = [for (var i = chunkCount - 1; i >= 0; i--) if (!done.contains(i)) i];
      final attempts = <int, int>{};
      // Bytes of each in-flight piece, so a failed piece takes back exactly
      // its own progress, not other connections'.
      final inFlight = <int, int>{};
      Object? fatal;

      Future<void> fetchPiece(int i) async {
        final start = chunkStart(i), end = chunkEnd(i);
        final request = await client.getUrl(Uri.parse(pkg.url));
        request.followRedirects = true;
        request.maxRedirects = 12;
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${end - 1}');
        final response = await request.close();
        if (response.statusCode != HttpStatus.partialContent) {
          unawaited(response.listen(null).cancel());
          throw HttpException('piece $i answered HTTP ${response.statusCode}');
        }
        var at = start;
        await for (final bytes in response.timeout(stallTimeout)) {
          if (cancelToken?.isCancelled ?? false) {
            throw const ModelDownloadException('Download cancelled.');
          }
          if (fatal != null) return;
          if (at + bytes.length > end) throw HttpException('piece $i overran its range');
          final pos = at;
          at += bytes.length;
          await locked(() async {
            await raf.setPosition(pos);
            await raf.writeFrom(bytes);
          });
          received += bytes.length;
          inFlight[i] = (inFlight[i] ?? 0) + bytes.length;
          emitProgress(ModelDownloadState(
            phase: DownloadPhase.downloading,
            receivedBytes: received,
            totalBytes: total,
          ));
        }
        if (at != end) throw HttpException('piece $i ended early');
        await locked(() async {
          await sidecar.writeAsString('$i\n', mode: FileMode.append, flush: true);
        });
      }

      Future<void> worker() async {
        while (queue.isNotEmpty && fatal == null) {
          final i = queue.removeLast();
          try {
            await fetchPiece(i);
            inFlight.remove(i);
          } on ModelDownloadException catch (e) {
            fatal ??= e;
            return;
          } on Object catch (e) {
            // A dropped piece is re-queued from its start; its partial bytes
            // are simply overwritten.
            received -= inFlight.remove(i) ?? 0;
            final n = (attempts[i] ?? 0) + 1;
            attempts[i] = n;
            if (n >= _chunkAttempts) {
              fatal ??= ModelDownloadException(
                'Network error: $e. The download resumes where it stopped when '
                'you try again.',
              );
              return;
            }
            queue.add(i);
            await Future<void>.delayed(Duration(milliseconds: 500 * n));
          }
        }
      }

      final workers = connections < chunkCount ? connections : chunkCount;
      await Future.wait([for (var w = 0; w < workers; w++) worker()]);
      await writeLock;
      await raf.flush();
      await raf.close();

      final failure = fatal;
      if (failure is ModelDownloadException) throw failure;
      if (failure != null) throw ModelDownloadException('$failure');

      emit(ModelDownloadState(
        phase: DownloadPhase.verifying,
        receivedBytes: total,
        totalBytes: total,
      ));
      if (pkg.sha256.isNotEmpty) {
        final digestHex = await _sha256OfFileInIsolate(partial.path);
        if (digestHex != pkg.sha256) {
          await partial.delete();
          await sidecar.delete();
          throw const ModelDownloadException(
            'The downloaded file failed its integrity check and was removed. '
            'This usually means the download was corrupted — try again.',
          );
        }
      }

      final target = File(targetPath);
      if (await target.exists()) await target.delete();
      await partial.rename(targetPath);
      if (await sidecar.exists()) await sidecar.delete();
      emit(ModelDownloadState(
        phase: DownloadPhase.done,
        receivedBytes: total,
        totalBytes: total,
      ));
      return targetPath;
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
  }

  String _httpMessage(int status, ModelPackage pkg) {
    if (status == HttpStatus.notFound) {
      return 'The classroom package is not published yet (HTTP 404). '
          'Check the Hugging Face package catalog and try again.';
    }
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      return 'The package location refused the download (HTTP $status).';
    }
    return 'Download failed with HTTP $status.';
  }

  /// Refuses to start a download that cannot possibly fit.
  ///
  /// Running out of storage 600 MB into a metered download is the worst
  /// failure available to this user, so the check is worth spending up front.
  /// Not every platform can report free space; an unknown answer is allowed
  /// through rather than blocking a download that would have been fine.
  Future<void> _ensureSpaceFor(
    ModelPackage pkg,
    String targetPath, {
    required int alreadyHave,
  }) async {
    final needed = pkg.approxBytes - alreadyHave;
    if (needed <= 0) return;
    try {
      final free = await _freeBytes(File(targetPath).parent.path);
      if (free != null && free < needed) {
        throw ModelDownloadException(
          'Not enough storage. The ${pkg.label.toLowerCase()} needs about '
          '${_mb(needed)} MB free, but only ${_mb(free)} MB is available.',
        );
      }
    } on ModelDownloadException {
      rethrow;
    } catch (_) {
      // Free-space reporting is best effort.
    }
  }

  static int _mb(int bytes) => (bytes / (1024 * 1024)).round();

  Future<int?> _freeBytes(String dirPath) async {
    if (Platform.isAndroid || Platform.isLinux) {
      final r = await Process.run('df', ['-k', dirPath]);
      if (r.exitCode != 0) return null;
      final lines = (r.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      final cols = lines.last.trim().split(RegExp(r'\s+'));
      if (cols.length < 4) return null;
      final kb = int.tryParse(cols[3]);
      return kb == null ? null : kb * 1024;
    }
    return null;
  }
}

/// SHA-256 of a file, computed off the UI thread — hashing ~1 GB takes
/// seconds on a phone. Top-level on purpose: `Isolate.run` copies the
/// closure's captured scope, and a closure made inside the downloader would
/// drag along unsendable state (pending futures, file handles).
Future<String> _sha256OfFileInIsolate(String path) =>
    Isolate.run(() => _sha256OfFile(path));

Future<String> _sha256OfFile(String path) async {
  final digest = _Sha256Accumulator();
  await for (final chunk in File(path).openRead()) {
    digest.add(chunk);
  }
  return digest.close().toString();
}

/// Feeds chunks into a SHA-256 as they stream past, so verification needs no
/// second pass over the file.
class _Sha256Accumulator {
  _Sha256Accumulator() {
    _inner = sha256.startChunkedConversion(_out);
  }

  final _DigestCatcher _out = _DigestCatcher();
  late final ByteConversionSink _inner;

  void add(List<int> chunk) => _inner.add(chunk);

  Digest close() {
    _inner.close();
    return _out.value!;
  }
}

class _DigestCatcher implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

extension on ModelPackage {
  ModelPackage copyWithUrl(String url) => ModelPackage(
        id: id,
        label: label,
        fileName: fileName,
        url: url,
        // `this.` — a bare `sha256` here is package:crypto's hash function.
        sha256: this.sha256,
        approxBytes: approxBytes,
        essential: essential,
        mirrors: mirrors,
      );
}
