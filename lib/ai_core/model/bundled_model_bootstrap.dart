import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../translate/afrislm_model_manager.dart';
import 'model_manager.dart';

/// Result of ensuring APK-bundled models are on disk for the engines.
class BundledModelBootstrapResult {
  const BundledModelBootstrapResult({
    required this.chatReady,
    required this.translateReady,
    required this.extractedAnything,
    this.chatBundledInApk = false,
    this.error,
  });

  /// True when the chat model is being served in place from the APK's own
  /// assets rather than from a file in app storage — the engine then loads
  /// it via flutter_gemma's `fromBundled`, and nothing is extracted.
  final bool chatBundledInApk;

  final bool chatReady;
  final bool translateReady;
  final bool extractedAnything;
  final String? error;
}

/// Prepares the APK-bundled models for the engines on first launch.
///
/// Only the translation GGUF is extracted: llama.cpp opens a filesystem
/// path, not an AssetManager entry. The chat model stays inside the APK and
/// is loaded in place by LiteRT-LM via flutter_gemma's `fromBundled`, so it
/// is stored exactly once on the device instead of twice.
///
/// Slim / debug APKs without those assets no-op and leave "Install from file"
/// as the install path. Desktop builds are skipped (they use exe-adjacent
/// `models/` from the release zip).
class BundledModelBootstrap {
  BundledModelBootstrap({
    ModelManager? chatManager,
    AfriSlmModelManager? translateManager,
  })  : _chat = chatManager ?? ModelManager(),
        _translate = translateManager ?? AfriSlmModelManager();

  static const _channelName = 'ai_connect_africa/bundled_models';
  static const chatAssetPath = 'models/${ModelManager.chatModelFileName}';

  /// Fat APK / asset-pack names. Install Packages uses Q4; Windows zips and
  /// older fat APKs still ship `translate-afrislm.gguf`.
  static List<String> get translateAssetCandidates => [
        for (final name in AfriSlmModelManager.allFileNames) 'models/$name',
      ];

  final ModelManager _chat;
  final AfriSlmModelManager _translate;
  final MethodChannel _channel = const MethodChannel(_channelName);

  /// Reports 0..1 overall progress while extracting (null when nothing to do).
  Future<BundledModelBootstrapResult> ensureExtracted({
    void Function(double progress, String label)? onProgress,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      try {
        final chat = await _chat.checkModel();
        final translate = await _translate.checkModel();
        return BundledModelBootstrapResult(
          chatReady: chat.isReady,
          translateReady: translate.isReady,
          extractedAnything: false,
        );
      } catch (e) {
        debugPrint('BundledModelBootstrap desktop probe failed: $e');
        return const BundledModelBootstrapResult(
          chatReady: false,
          translateReady: false,
          extractedAnything: false,
          error: 'desktop model probe failed',
        );
      }
    }

    try {
      final chatInfo = await _chat.checkModel();
      final translateInfo = await _translate.checkModel();
      final hasChatAsset = await _hasAsset(chatAssetPath);
      String? translateAsset;
      for (final asset in translateAssetCandidates) {
        if (await _hasAsset(asset)) {
          translateAsset = asset;
          break;
        }
      }

      var extracted = false;
      String? error;

      // The chat model is NOT extracted when the APK carries it. LiteRT-LM
      // reads the asset in place, so copying it into app storage would just
      // be a second ~600 MB of the same bytes. Translation still needs a
      // real file: llama.cpp opens a path, not an AssetManager entry.
      final steps = <({String asset, String dest, String label})>[];
      if (!translateInfo.isReady && translateAsset != null) {
        steps.add((
          asset: translateAsset,
          dest: await _translate.modelFilePath(),
          label: 'Translation model',
        ));
      }

      if (steps.isEmpty) {
        return BundledModelBootstrapResult(
          chatReady: chatInfo.isReady || hasChatAsset,
          chatBundledInApk: hasChatAsset && !chatInfo.isReady,
          translateReady: translateInfo.isReady,
          extractedAnything: false,
        );
      }

      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final base = i / steps.length;
        final span = 1.0 / steps.length;
        onProgress?.call(base, 'Preparing ${step.label}…');
        try {
          await _extract(
            assetPath: step.asset,
            destPath: step.dest,
            onProgress: (p) =>
                onProgress?.call(base + p * span, 'Preparing ${step.label}…'),
          );
          extracted = true;
        } catch (e) {
          error = e.toString();
          break;
        }
      }

      final chatAfter = await _chat.checkModel();
      final translateAfter = await _translate.checkModel();
      return BundledModelBootstrapResult(
        chatReady: chatAfter.isReady || hasChatAsset,
        chatBundledInApk: hasChatAsset && !chatAfter.isReady,
        translateReady: translateAfter.isReady,
        extractedAnything: extracted,
        error: error,
      );
    } on MissingPluginException {
      final chat = await _chat.checkModel();
      final translate = await _translate.checkModel();
      return BundledModelBootstrapResult(
        chatReady: chat.isReady,
        translateReady: translate.isReady,
        extractedAnything: false,
      );
    }
  }

  /// Falls back to a real file when LiteRT-LM cannot load the chat model
  /// straight out of the APK. Costs a second ~600 MB copy, so it only runs
  /// after an in-place load has actually failed.
  Future<String> materializeChatModel({
    void Function(double progress)? onProgress,
  }) async {
    final dest = await _chat.installTargetPath();
    await _extract(
      assetPath: chatAssetPath,
      destPath: dest,
      onProgress: onProgress,
    );
    return dest;
  }

  Future<bool> _hasAsset(String assetPath) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasBundledAsset',
        {'assetPath': assetPath},
      );
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _extract({
    required String assetPath,
    required String destPath,
    void Function(double progress)? onProgress,
  }) async {
    await Directory(p.dirname(destPath)).create(recursive: true);

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'extractProgress') return;
      final args = call.arguments;
      if (args is! Map) return;
      if (args['assetPath'] != assetPath) return;
      final progress = (args['progress'] as num?)?.toDouble();
      if (progress != null) onProgress?.call(progress);
    });

    try {
      await _channel.invokeMethod<bool>(
        'extractBundledAsset',
        {'assetPath': assetPath, 'destPath': destPath},
      );
    } on PlatformException catch (e) {
      throw StateError(e.message ?? e.toString());
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
