import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/gguf_file.dart';
import '../model/model_locations.dart';
import '../model/model_manager.dart' show ModelInfo, ModelStatus;
import '../model/device_tier.dart';
import '../model/model_runtime_policy.dart';

/// Locates and installs the TranslatePsy-AfriSLM translation model.
///
/// One format per platform (model_runtime_policy.dart):
/// - Android → `afrislm-0.8b_int8.litertlm` on LiteRT-LM (converted by
///   `.github/workflows/convert-afrislm-litertlm.yml`).
/// - Windows / Linux → the Q4 GGUF on llama.cpp.
class AfriSlmModelManager {
  /// Canonical desktop file — matches Hugging Face Install Packages
  /// (`ModelFetchFiles.translate`) and `assets/models/` tooling.
  static const ggufFileName = 'afrislm-0.8b-q4_k_m.gguf';

  /// Android int8 build (phones with more than ~5 GB).
  static const liteRtFileName = 'afrislm-0.8b_int8.litertlm';

  /// Android int4 build for 4 GB phones — see [DeviceTier].
  static const liteRtInt4FileName = 'afrislm-0.8b_int4.litertlm';

  /// The Android file this phone downloads.
  static String get liteRtPreferredFileName =>
      DeviceTier.current.isLowMemory ? liteRtInt4FileName : liteRtFileName;

  /// This platform's canonical file.
  static String get modelFileName =>
      androidUsesLiteRt ? liteRtPreferredFileName : ggufFileName;

  /// USB / release / older quants still accepted on desktop so a
  /// `translate-afrislm.gguf` next to the exe keeps working.
  static const alternateGgufFileNames = [
    'translate-afrislm.gguf',
    'afrislm-0.8b-q8_0.gguf',
    'afrislm-0.8b-q5_k_m.gguf',
    'TranslatePsy-AfriSLM-0.8B.Q4_K_M.gguf',
    'TranslatePsy-AfriSLM-0.8B-Q8_0-imat.gguf',
    'TranslatePsy-AfriSLM-0.8B-Q4_K_M-imat.gguf',
  ];
  static const _markerFileName = 'translate-afrislm.install.json';
  // Q4 GGUF ~640 MB, int8 .litertlm ~0.9 GB; reject obvious truncations.
  static const _minSizeBytes = 300 * 1024 * 1024; // 300 MB

  /// Canonical name first, then this platform's accepted aliases.
  /// On Android both builds are accepted, this phone's preferred one first,
  /// so an int8 already on disk keeps working on a 4 GB phone.
  static List<String> get allFileNames => androidUsesLiteRt
      ? (DeviceTier.current.isLowMemory
          ? const [liteRtInt4FileName, liteRtFileName]
          : const [liteRtFileName, liteRtInt4FileName])
      : const [ggufFileName, ...alternateGgufFileNames];

  /// Canonical install target — where [installFromFile] and
  /// [downloadModel] write the file.
  Future<String> modelFilePath() async {
    return canonicalModelInstallPath(modelFileName);
  }

  /// All locations checked for an already-present model file, in order.
  /// Mirrors ModelManager: canonical install path first, then a
  /// bundled-next-to-the-executable fallback so a self-contained release
  /// zip (exe + models/translate-afrislm.gguf) is picked up automatically.
  Future<List<String>> _candidatePathsFor(String fileName) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return modelCandidateFiles(fileName);
    }

    final paths = <String>[
      await canonicalModelInstallPath(fileName),
      ...await modelCandidateFiles(fileName),
    ];
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        paths.add(
          p.join(
            ext.parent.parent.parent.parent.path,
            'OTIC',
            fileName,
          ),
        );
      }
    } catch (_) {}
    try {
      final appFiles = await getApplicationDocumentsDirectory();
      paths.add(p.join(appFiles.path, 'models', fileName));
    } catch (_) {}
    try {
      final support = await getApplicationSupportDirectory();
      paths.add(p.join(support.path, 'models', fileName));
    } catch (_) {}
    final seen = <String>{};
    return [
      for (final path in paths)
        if (seen.add(p.normalize(path))) p.normalize(path),
    ];
  }

  Future<List<String>> _candidatePaths() async {
    final names = allFileNames;
    final out = <String>[];
    for (final name in names) {
      out.addAll(await _candidatePathsFor(name));
    }
    return out;
  }

  Future<ModelInfo> checkModel() async {
    final candidates = await _candidatePaths();
    debugPrint('TRANSLATE MODEL candidates:\n  ${candidates.join('\n  ')}');
    ModelInfo? truncated;
    for (final path in candidates) {
      final file = File(path);
      try {
        if (!await file.exists()) continue;
      } catch (_) {
        continue;
      }
      final size = await file.length();
      if (size < _minSizeBytes) {
        truncated ??= ModelInfo(
          status: ModelStatus.corrupted,
          path: path,
          sizeBytes: size,
        );
        continue;
      }
      if (!androidUsesLiteRt && !await fileLooksLikeGguf(file)) {
        debugPrint('TRANSLATE MODEL skipped (not GGUF): $path');
        truncated ??= ModelInfo(
          status: ModelStatus.corrupted,
          path: path,
          sizeBytes: size,
        );
        continue;
      }
      return ModelInfo(status: ModelStatus.ready, path: path, sizeBytes: size);
    }
    return truncated ?? const ModelInfo(status: ModelStatus.notInstalled);
  }

  /// Copies a user-picked GGUF file into the expected location. Mirrors
  /// ModelManager.installFromFile's atomic `.part` rename + size validation.
  Future<ModelInfo> installFromFile(
    String sourcePath, {
    void Function(double progress)? onProgress,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const AfriSlmInstallException('The selected file no longer exists.');
    }

    if (!isAllowedModelPath(sourcePath)) {
      throw AfriSlmInstallException(
        'Wrong file type. On this device the translation model is $modelFileName.',
      );
    }

    final size = await source.length();
    if (size < _minSizeBytes) {
      throw const AfriSlmInstallException(
        'That file is too small to be the AfriSLM translation model — it '
        'should be at least a few hundred MB. The download or copy may be '
        'incomplete.',
      );
    }

    final targetPath = await modelFilePath();
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    final partial = File('$targetPath.part');
    final sink = partial.openWrite();
    var copied = 0;
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copied += chunk.length;
        onProgress?.call(copied / size);
      }
      await sink.flush();
      await sink.close();
      if (await target.exists()) await target.delete();
      await partial.rename(targetPath);
      await _writeMarker(sourceUrl: null, sizeBytes: size);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await partial.exists()) await partial.delete();
      if (e is FileSystemException) {
        throw const AfriSlmInstallException(
          'Could not copy the model — the device may not have enough '
          'free storage (about 1 GB is needed).',
        );
      }
      rethrow;
    }
    return checkModel();
  }

  /// Downloads the GGUF from a direct URL with progress, atomically
  /// installing it only once fully received.
  Future<ModelInfo> downloadModel(
    String url, {
    void Function(AfriSlmDownloadProgress progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AfriSlmInstallException('Enter a valid model URL.');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const AfriSlmInstallException(
        'The model URL must start with http:// or https://.',
      );
    }

    final targetPath = await modelFilePath();
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    final partial = File('$targetPath.part');
    if (await partial.exists()) await partial.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = 'AI Connect Africa AfriSLM downloader';

    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AfriSlmInstallException(
          'Download failed with HTTP ${response.statusCode}.',
        );
      }

      final total = response.contentLength > 0 ? response.contentLength : null;
      var received = 0;
      sink = partial.openWrite();

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          AfriSlmDownloadProgress(receivedBytes: received, totalBytes: total),
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final size = await partial.length();
      if (size < _minSizeBytes) {
        throw const AfriSlmInstallException(
          'The downloaded file is too small for the AfriSLM model. '
          'Check that the URL points directly to the model file.',
        );
      }

      if (await target.exists()) await target.delete();
      await partial.rename(targetPath);
      await _writeMarker(sourceUrl: uri.toString(), sizeBytes: size);
      return ModelInfo(status: ModelStatus.ready, path: targetPath, sizeBytes: size);
    } on AfriSlmInstallException {
      rethrow;
    } on FileSystemException {
      throw const AfriSlmInstallException(
        'Could not save the model. The device may not have enough free storage.',
      );
    } on SocketException catch (e) {
      throw AfriSlmInstallException('Network error: ${e.message}');
    } finally {
      client.close(force: true);
      try {
        await sink?.close();
      } catch (_) {}
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  Future<File> _markerFile() async {
    return File(await canonicalModelInstallPath(_markerFileName));
  }

  Future<void> _writeMarker({
    required String? sourceUrl,
    required int sizeBytes,
  }) async {
    try {
      final marker = await _markerFile();
      await marker.parent.create(recursive: true);
      await marker.writeAsString(
        jsonEncode({
          'installed': true,
          'modelFileName': modelFileName,
          'sourceUrl': sourceUrl,
          'sizeBytes': sizeBytes,
          'installedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Marker is informational only — never block install on it.
    }
  }
}

class AfriSlmInstallException implements Exception {
  const AfriSlmInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AfriSlmDownloadProgress {
  const AfriSlmDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return receivedBytes / total;
  }
}
