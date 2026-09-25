import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../ai_core/model/model_download_service.dart';
import '../ai_core/model/model_locations.dart';
import '../ai_core/model/model_manager.dart';
import '../ai_core/model/model_package.dart';
import '../ai_core/model/model_runtime_policy.dart';
import '../ai_core/providers/ai_provider.dart';
import '../ai_core/translate/afrislm_model_manager.dart';

/// Hugging Face `resolve/main` base for classroom packages.
///
/// Default: public [Oticgroup/ai-connect-africa-packages]. Override with
/// `--dart-define=OTIC_HF_MODELS_BASE=https://huggingface.co/.../resolve/main`
/// at build time. No trailing slash.
const kModelFetchHfBaseUrl = String.fromEnvironment(
  'OTIC_HF_MODELS_BASE',
  defaultValue:
      'https://huggingface.co/Oticgroup/ai-connect-africa-packages/resolve/main',
);

/// On-disk names under `<app documents>/models/` (never shown in UI).
///
/// One format per platform (model_runtime_policy.dart): Android downloads
/// the two LiteRT-LM `.litertlm` builds, desktop the two GGUFs. Filenames
/// match the HF package repo so Install Packages can resolve without
/// rewriting; SHA-256 pins match what CI publishes.
class ModelFetchFiles {
  // ── Desktop (llama.cpp) ────────────────────────────────────────────────
  static const chatGguf = ModelManager.brainGgufFileName;
  static const chatGgufSha256 =
      'cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046';
  static const chatGgufApproxBytes = 1117320768;

  static const translateGguf = AfriSlmModelManager.ggufFileName;
  static const translateGgufSha256 =
      '4af8ee1df3ec9008f763ebe95e6f21df3acd8d42c541feeb13314ca22e560afc';
  static const translateGgufApproxBytes = 672329792;

  // ── Android (LiteRT-LM) ────────────────────────────────────────────────
  /// litert-community's int4 build of the same brain, mirrored.
  static const chatLiteRt = ModelManager.brainLiteRtFileName;
  static const chatLiteRtSha256 =
      '273ecc7771ba2dd5fe1bb6d4d4726ad0353102f04ad094082ccf59bca9f21213';
  static const chatLiteRtApproxBytes = 1117385648;

  /// AfriSLM converted by .github/workflows/convert-afrislm-litertlm.yml.
  /// Empty until that job publishes it — the download then skips the hash
  /// check but still rejects truncated files by size.
  /// int8 on every phone (see AfriSlmModelManager.liteRtFileName).
  static String get translateLiteRt => AfriSlmModelManager.liteRtFileName;
  static const translateLiteRtSha256 =
      'f5a356714430f7174f970411148601118e38dc5a7b524ff920d3d0bef122579a';
  static const translateLiteRtApproxBytes = 898256944;

  /// No alternative translator build is published.
  static String? get translateFallback => null;

  /// GitHub release the conversion workflow publishes both .litertlm files
  /// to — a mirror while the Hugging Face repo is being filled.
  static const liteRtReleaseBase =
      'https://github.com/EccentricIvan/AI-CONNECT-AFRICA/releases/download/litert-models';

  /// litert-community, pinned to the revision whose hash is above.
  static const chatLiteRtUpstream =
      'https://huggingface.co/litert-community/Qwen2.5-Coder-1.5B-Instruct/resolve/'
      'ddb8ab66e162dd89328da9bc144d1d626d3f2c9f/Qwen2.5-Coder-1.5B-Instruct_int4.litertlm';

  // ── This platform ──────────────────────────────────────────────────────
  static String get chat => androidUsesLiteRt ? chatLiteRt : chatGguf;
  static String get chatSha256 =>
      androidUsesLiteRt ? chatLiteRtSha256 : chatGgufSha256;
  static int get chatApproxBytes =>
      androidUsesLiteRt ? chatLiteRtApproxBytes : chatGgufApproxBytes;

  static String get translate =>
      androidUsesLiteRt ? translateLiteRt : translateGguf;
  static String get translateSha256 =>
      androidUsesLiteRt ? translateLiteRtSha256 : translateGgufSha256;
  static int get translateApproxBytes =>
      androidUsesLiteRt ? translateLiteRtApproxBytes : translateGgufApproxBytes;

  static List<String> get chatMirrors => androidUsesLiteRt
      ? const ['$liteRtReleaseBase/$chatLiteRt', chatLiteRtUpstream]
      : const [];
  static List<String> get translateMirrors => androidUsesLiteRt
      ? ['$liteRtReleaseBase/$translateLiteRt']
      : const [];

  /// Coding runs on the brain; there is no separate coder file.
  static String get coder => chat;
}

enum ModelFetchPhase { idle, ready, fetching, failed }

/// White-label combined progress for the classroom package queue.
@immutable
class ModelFetchUiState {
  const ModelFetchUiState({
    this.phase = ModelFetchPhase.idle,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.statusLabel = '',
    this.error,
    this.coderReady = false,
  });

  final ModelFetchPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String statusLabel;
  final String? error;

  /// True when the on-demand coding package is already on disk.
  final bool coderReady;

  bool get isReady => phase == ModelFetchPhase.ready;

  bool get isFetching => phase == ModelFetchPhase.fetching;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  ModelFetchUiState copyWith({
    ModelFetchPhase? phase,
    int? receivedBytes,
    int? totalBytes,
    String? statusLabel,
    String? error,
    bool? coderReady,
    bool clearError = false,
  }) {
    return ModelFetchUiState(
      phase: phase ?? this.phase,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      statusLabel: statusLabel ?? this.statusLabel,
      error: clearError ? null : (error ?? this.error),
      coderReady: coderReady ?? this.coderReady,
    );
  }
}

/// Multi-package HF downloader with one-time-on-disk semantics.
///
/// * **Core Fetch Packages** → tutor + translation only.
/// * **Coder** → separate on-demand fetch when a programming surface opens.
/// * If a target file already exists and passes the size floor, that package
///   is **never** re-downloaded unless the student deletes it.
class ModelFetchService {
  ModelFetchService({
    ModelDownloadService? downloader,
    this.hfBaseUrl = kModelFetchHfBaseUrl,
  }) : _downloader = downloader ?? ModelDownloadService();

  final ModelDownloadService _downloader;
  final String hfBaseUrl;

  CancellationToken? _token;

  static ModelPackage get coreChatPackage => ModelPackage(
    id: 'core_chat',
    label: 'Classroom package',
    fileName: ModelFetchFiles.chat,
    url: '$kModelFetchHfBaseUrl/${ModelFetchFiles.chat}',
    sha256: ModelFetchFiles.chatSha256,
    approxBytes: ModelFetchFiles.chatApproxBytes,
    essential: true,
    mirrors: ModelFetchFiles.chatMirrors,
  );

  static ModelPackage get coreTranslatePackage => ModelPackage(
    id: 'core_translate',
    label: 'Classroom package',
    fileName: ModelFetchFiles.translate,
    url: '$kModelFetchHfBaseUrl/${ModelFetchFiles.translate}',
    sha256: ModelFetchFiles.translateSha256,
    approxBytes: ModelFetchFiles.translateApproxBytes,
    essential: true,
    mirrors: ModelFetchFiles.translateMirrors,
  );

  /// Coding runs on the brain, so "the coder package" is the brain package.
  static ModelPackage get coderPackage => coreChatPackage;

  static List<ModelPackage> get corePackages => [
    coreChatPackage,
    coreTranslatePackage,
  ];

  /// Every package Install Packages pulls: the brain and the translator.
  static List<ModelPackage> get allPackages => corePackages;

  /// Canonical install directory (same as USB / manager discovery).
  ///
  /// Android → `<app documents>/models/`
  /// Desktop → `<Documents>/OTIC/`
  Future<Directory> modelsDirectory({bool ensure = true}) async {
    final probe = await canonicalModelInstallPath('_', ensureDirectory: ensure);
    return Directory(p.dirname(probe));
  }

  Future<String> pathFor(String fileName) async {
    return canonicalModelInstallPath(fileName, ensureDirectory: true);
  }

  /// True when discovery already finds a usable file (any known location /
  /// alias) — not only the HF download target — so USB/bundled installs
  /// skip network pulls.
  Future<bool> isPackagePresent(ModelPackage pkg) async {
    switch (pkg.id) {
      case 'core_chat':
        return (await ModelManager().checkModel()).isReady;
      case 'core_translate':
        return (await AfriSlmModelManager().checkModel()).isReady;
      default:
        final path = await pathFor(pkg.fileName);
        return _fileReady(path, pkg.approxBytes);
    }
  }

  bool _fileReady(String path, int approxBytes) {
    final file = File(path);
    if (!file.existsSync()) return false;
    try {
      final len = file.lengthSync();
      final floor = (approxBytes * 0.45).floor();
      return len >= floor;
    } catch (_) {
      return false;
    }
  }

  Future<bool> areCorePackagesReady() async {
    for (final pkg in corePackages) {
      if (!await isPackagePresent(pkg)) return false;
    }
    return true;
  }

  /// True when the brain and the translator are both discoverable.
  Future<bool> areAllPackagesReady() async {
    for (final pkg in allPackages) {
      if (!await isPackagePresent(pkg)) return false;
    }
    return true;
  }

  /// Pre-flight used by the Install Packages screen / ModelGate.
  ///
  /// True when both packages are already on disk — the UI
  /// must skip the installer and go straight to home.
  Future<bool> checkPackagesCached() => areAllPackagesReady();

  Future<bool> isCoderReady() => isPackagePresent(coderPackage);

  /// Sequential install of **all** packages as a progress stream (white-label).
  ///
  /// Never emits filenames, byte totals for display, or storage paths —
  /// only [ModelFetchUiState] with [fraction] + [statusLabel].
  Stream<ModelFetchUiState> fetchMissingPackages() async* {
    final queue = StreamController<ModelFetchUiState>();
    final done =
        fetchAllPackages(
          onState: (s) {
            if (!queue.isClosed) queue.add(s);
          },
        ).whenComplete(() {
          if (!queue.isClosed) queue.close();
        });
    yield* queue.stream;
    await done;
  }

  /// White-label status line from combined progress (0..1).
  static String whiteLabelStatus(double fraction, {required bool connecting}) {
    if (connecting && fraction <= 0) {
      return 'Initializing offline classroom systems...';
    }
    if (fraction < 0.22) return 'Setting up regional workspace...';
    if (fraction < 0.55) return 'Optimizing formula drivers...';
    if (fraction < 0.85) return 'Preparing studio tools...';
    return 'Finalizing tutor environment...';
  }

  static String whiteLabelCoderStatus(
    double fraction, {
    required bool connecting,
  }) {
    if (connecting && fraction <= 0) {
      return 'Initializing offline classroom systems...';
    }
    if (fraction < 0.85) return 'Optimizing formula drivers...';
    return 'Finalizing tutor environment...';
  }

  void cancel() => _token?.cancel();

  /// Fetch the brain and the translator in one Install Packages pass.
  /// Skips any file already on disk.
  Future<ModelFetchUiState> fetchAllPackages({
    void Function(ModelFetchUiState state)? onState,
  }) async {
    if (await areAllPackagesReady()) {
      const ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        receivedBytes: 1,
        totalBytes: 1,
        coderReady: true,
      );
      onState?.call(ready);
      return ready;
    }

    final token = CancellationToken();
    _token = token;

    final planned = <ModelPackage>[];
    var alreadyBytes = 0;
    var plannedBytes = 0;
    for (final pkg in allPackages) {
      if (await isPackagePresent(pkg)) {
        alreadyBytes += pkg.approxBytes;
      } else {
        planned.add(pkg);
        plannedBytes += pkg.approxBytes;
      }
    }
    final totalBytes = alreadyBytes + plannedBytes;

    var received = alreadyBytes;
    void emit(ModelFetchUiState s) => onState?.call(s);

    emit(
      ModelFetchUiState(
        phase: ModelFetchPhase.fetching,
        receivedBytes: received,
        totalBytes: totalBytes,
        statusLabel: whiteLabelStatus(0, connecting: true),
        coderReady: await isCoderReady(),
      ),
    );

    var translatorPending = false;
    try {
      for (final pkg in planned) {
        // One-time rule: re-check immediately before each network pull.
        if (await isPackagePresent(pkg)) {
          received += pkg.approxBytes;
          continue;
        }

        final target = await pathFor(pkg.fileName);
        final pkgBase = received;
        final remote = pkg.copyWith(url: '$hfBaseUrl/${pkg.fileName}');
        try {
          await _downloader.download(
            remote,
            targetPath: target,
            cancelToken: token,
            onState: (s) {
              final local = s.receivedBytes;
              final combined = pkgBase + local;
              final frac = totalBytes <= 0 ? 0.0 : combined / totalBytes;
              emit(
                ModelFetchUiState(
                  phase: ModelFetchPhase.fetching,
                  receivedBytes: combined,
                  totalBytes: totalBytes,
                  statusLabel: whiteLabelStatus(
                    frac,
                    connecting: s.phase == DownloadPhase.connecting,
                  ),
                  coderReady: false,
                ),
              );
            },
          );
        } on ModelDownloadException catch (e) {
          // The translator is not yet published everywhere (the Android
          // .litertlm comes from a conversion job). A missing translator must
          // not block the tutor: skip it, finish setup English-only, and a
          // later Install Packages picks it up.
          final notPublished = e.message.contains('HTTP 404');
          if (pkg.id != coreTranslatePackage.id || !notPublished) rethrow;
          final fallback = ModelFetchFiles.translateFallback;
          var gotFallback = false;
          if (fallback != null) {
            try {
              await _downloader.download(
                ModelPackage(
                  id: pkg.id,
                  label: pkg.label,
                  fileName: fallback,
                  url: '$hfBaseUrl/$fallback',
                  sha256: '',
                  approxBytes: 898256944,
                  essential: false,
                  mirrors: ['${ModelFetchFiles.liteRtReleaseBase}/$fallback'],
                ),
                targetPath: await pathFor(fallback),
                cancelToken: token,
              );
              gotFallback = true;
            } on ModelDownloadException catch (e2) {
              if (!e2.message.contains('HTTP 404')) rethrow;
            }
          }
          if (!gotFallback) translatorPending = true;
          debugPrint(
            'Translator package not published yet — continuing English-only.',
          );
        }
        received = pkgBase + pkg.approxBytes;
      }

      await removeStaleOtherFormatModels();

      // End-to-end gate: files must be discoverable by the same managers the
      // Windows/Android runtimes use — not merely written to disk.
      final brainReady = await isPackagePresent(coreChatPackage);
      if (!brainReady || (!translatorPending && !await areAllPackagesReady())) {
        throw const ModelDownloadException(
          'Packages downloaded but could not be verified on this device. '
          'Please try Install Packages again.',
        );
      }

      final ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        receivedBytes: totalBytes,
        totalBytes: totalBytes,
        statusLabel: translatorPending
            ? 'Ready (English). Local-language pack not published yet - tap Install again later.'
            : 'Ready',
        coderReady: true,
      );
      emit(ready);
      return ready;
    } on ModelDownloadException catch (e) {
      final failed = ModelFetchUiState(
        phase: ModelFetchPhase.failed,
        receivedBytes: received,
        totalBytes: totalBytes,
        statusLabel: 'Could not finish setup',
        error: e.message,
        coderReady: await isCoderReady(),
      );
      emit(failed);
      return failed;
    } finally {
      _token = null;
    }
  }

  /// Android runs LiteRT only, so GGUFs an older Android build downloaded
  /// (~1.8 GB) can never load again. Once this platform's own models are in
  /// place they are deleted to give the space back. Desktop keeps
  /// everything — nothing here touches a folder a student manages.
  Future<void> removeStaleOtherFormatModels() async {
    if (!androidUsesLiteRt) return;
    if (!await areAllPackagesReady()) return;
    try {
      final dir = await modelsDirectory(ensure: false);
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        final name = e.path.toLowerCase();
        if (e is File &&
            (name.endsWith('.gguf') || name.endsWith('.gguf.part'))) {
          debugPrint('Removing unused Android GGUF: ${e.path}');
          await e.delete();
        }
      }
    } catch (e) {
      debugPrint('stale GGUF cleanup skipped: $e');
    }
  }

  /// Alias kept for call sites / tests — Install Packages fetches everything.
  Future<ModelFetchUiState> fetchCorePackages({
    void Function(ModelFetchUiState state)? onState,
  }) => fetchAllPackages(onState: onState);

  /// Labs ask for "the coder"; that is the brain, fetched with everything else.
  Future<ModelFetchUiState> fetchCoderPackage({
    void Function(ModelFetchUiState state)? onState,
  }) async {
    if (await isCoderReady()) {
      const ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        receivedBytes: 1,
        totalBytes: 1,
        coderReady: true,
      );
      onState?.call(ready);
      return ready;
    }

    // Prefer completing the full set so labs stay aligned with Install Packages.
    return fetchAllPackages(onState: onState);
  }
}

extension _ModelPackageCopy on ModelPackage {
  ModelPackage copyWith({String? url}) => ModelPackage(
    id: id,
    label: label,
    fileName: fileName,
    url: url ?? this.url,
    sha256: sha256,
    approxBytes: approxBytes,
    essential: essential,
    mirrors: mirrors,
  );
}

final modelFetchServiceProvider = Provider<ModelFetchService>(
  (ref) => ModelFetchService(),
);

/// True when the brain and the translator are on disk (Install Packages done).
final classroomPackagesReadyProvider = FutureProvider<bool>((ref) async {
  return ref.watch(modelFetchServiceProvider).checkPackagesCached();
});

final modelFetchControllerProvider =
    StateNotifierProvider<ModelFetchController, ModelFetchUiState>(
      (ref) => ModelFetchController(ref),
    );

class ModelFetchController extends StateNotifier<ModelFetchUiState> {
  ModelFetchController(this._ref) : super(const ModelFetchUiState()) {
    refresh();
  }

  final Ref _ref;

  ModelFetchService get _svc => _ref.read(modelFetchServiceProvider);

  Future<void> refresh() async {
    try {
      final allReady = await _svc.areAllPackagesReady();
      final coder = await _svc.isCoderReady();
      if (!mounted) return;
      state = ModelFetchUiState(
        phase: allReady ? ModelFetchPhase.ready : ModelFetchPhase.idle,
        statusLabel: allReady ? 'Ready' : '',
        receivedBytes: allReady ? 1 : 0,
        totalBytes: allReady ? 1 : 0,
        coderReady: coder,
      );
    } catch (e) {
      debugPrint('ModelFetchController refresh: $e');
    }
  }

  Future<void> fetchCore() async {
    if (state.isFetching) return;
    if (await _svc.areAllPackagesReady()) {
      state = const ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        receivedBytes: 1,
        totalBytes: 1,
        coderReady: true,
      );
      _invalidateClassroomStack();
      return;
    }

    final result = await _svc.fetchAllPackages(
      onState: (s) {
        if (mounted) state = s;
      },
    );
    if (!mounted) return;
    state = result;
    if (result.isReady) {
      _invalidateClassroomStack();
    }
  }

  Future<void> fetchCoder() async {
    if (state.isFetching) return;
    if (await _svc.isCoderReady() && await _svc.areAllPackagesReady()) {
      state = state.copyWith(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        coderReady: true,
      );
      _invalidateCoderStack();
      return;
    }

    final result = await _svc.fetchAllPackages(
      onState: (s) {
        if (mounted) state = s;
      },
    );
    if (!mounted) return;
    state = result;
    if (result.coderReady || result.isReady) {
      _invalidateClassroomStack();
      _invalidateCoderStack();
    }
  }

  void _invalidateClassroomStack() {
    _ref.invalidate(classroomPackagesReadyProvider);
    _ref.invalidate(modelInfoProvider);
    _ref.invalidate(translateModelInfoProvider);
    _ref.invalidate(programmingModelInfoProvider);
    _ref.invalidate(dualModelRuntimeProvider);
    _ref.invalidate(engineLoadedProvider);
    _ref.invalidate(translateEngineLoadedProvider);
    _ref.invalidate(translationPipelineProvider);
    _ref.invalidate(afrislmTranslationServiceProvider);
    _ref.invalidate(aiEngineServiceProvider);
    _ref.invalidate(tutorPipelineProvider);
    _ref.invalidate(qwenReasoningServiceProvider);
    _ref.invalidate(qwenChatServiceProvider);
    _ref.invalidate(chatInferencePipelineProvider);
    _ref.invalidate(programmingEngineProvider);
    _ref.invalidate(aiCoderServiceProvider);
    // Warm tutor + AfriSLM so the first local-language Learn turn works
    // without an English-only cold start after Install Packages.
    unawaited(() async {
      try {
        await _ref.read(dualModelRuntimeProvider.future);
        await ensureTranslationPipeline(_ref);
        await _ref.read(chatInferencePipelineProvider.future);
      } catch (e) {
        debugPrint('post-fetch AI warm failed: $e');
      }
    }());
  }

  void _invalidateCoderStack() {
    _ref.invalidate(programmingModelInfoProvider);
    _ref.invalidate(programmingEngineProvider);
    _ref.invalidate(aiCoderServiceProvider);
  }

  void cancel() => _svc.cancel();
}
