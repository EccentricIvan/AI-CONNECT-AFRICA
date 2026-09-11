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

/// Fetches a [ModelPackage] from the `model-pack` release to local storage.
///
/// Three things make this different from a plain GET, and all three exist
/// because the target device is a low-end phone on an expensive, unreliable
/// connection pulling up to 642 MB:
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

  /// Downloads [pkg] to [targetPath], reporting progress through [onState].
  ///
  /// Resumes from an existing `.part` file when one is present. Returns the
  /// final path on success; throws [ModelDownloadException] otherwise.
  Future<String> download(
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

    final client = _client ??
        (HttpClient()
          ..connectionTimeout = const Duration(seconds: 30)
          ..userAgent = 'AI Connect Africa model downloader');

    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(pkg.url));
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

      if (digest.close().toString() != pkg.sha256) {
        // Wrong bytes are worse than no bytes: keeping them would make every
        // later retry resume onto a corrupt prefix.
        await partial.delete();
        throw const ModelDownloadException(
          'The downloaded file failed its integrity check and was removed. '
          'This usually means the download was corrupted — try again.',
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
    } on FileSystemException {
      const msg = 'Could not save the model. The device may be out of storage.';
      emit(state.copyWith(phase: DownloadPhase.failed, error: msg));
      throw const ModelDownloadException(msg);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (_client == null) client.close(force: true);
    }
  }

  String _httpMessage(int status, ModelPackage pkg) {
    if (status == HttpStatus.notFound) {
      return 'The ${pkg.label.toLowerCase()} is not published yet (HTTP 404). '
          'The model-pack release may still be building.';
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
