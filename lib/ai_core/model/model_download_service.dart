import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
class ModelDownloadService {
  // ignore: prefer_initializing_formals
  ModelDownloadService({HttpClient? client}) : _client = client;

  /// Injected only by tests; production builds create a client per download.
  final HttpClient? _client;

  static const _maxAttempts = 3;

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
    void emit(ModelDownloadState next) {
      state = next;
      onState?.call(next);
    }

    emit(state);

    var resumeFrom = 0;
    if (await partial.exists()) {
      resumeFrom = await partial.length();
    }

    await _ensureSpaceFor(pkg, targetPath, alreadyHave: resumeFrom);

    final ownsClient = _client == null;
    final client = _client ?? _createClient();

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

      await for (final chunk in response) {
        if (cancelToken?.isCancelled ?? false) {
          // Cancelling is not discarding: the .part stays so the next
          // attempt resumes from here instead of re-spending the data.
          throw const ModelDownloadException('Download cancelled.');
        }
        sink.add(chunk);
        digest.add(chunk);
        received += chunk.length;
        emit(state.copyWith(
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
