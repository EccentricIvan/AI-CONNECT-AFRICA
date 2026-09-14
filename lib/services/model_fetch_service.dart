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
import '../ai_core/model/programming_model_manager.dart';
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
/// Filenames match the HF package repo so Install Packages can resolve
/// without rewriting. Discovery managers also accept legacy aliases.
class ModelFetchFiles {
  /// Android LiteRT tutor; desktop llama.cpp GGUF.
  static String get chat => useLiteRtChatBrain
      ? ModelManager.chatModelFileName
      : ModelManager.qwenGgufFileName;

  static String get chatSha256 => useLiteRtChatBrain
      ? '555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4'
      : 'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a';

  static int get chatApproxBytes =>
      useLiteRtChatBrain ? 614236160 : 396705472;

  static const translate = 'afrislm-0.8b-q4_k_m.gguf';
  static const translateSha256 =
      '4af8ee1df3ec9008f763ebe95e6f21df3acd8d42c541feeb13314ca22e560afc';
  static const translateApproxBytes = 672329792;

  /// Preferred Android LiteRT name (upload when available).
  static const coderLiteRt = 'qwen_coder_1.5b.litertlm';

  /// HF package currently ships this GGUF for Windows/Linux (and Android
  /// fallback until a LiteRT coder artifact is published).
  static const coderGguf = 'qwen2.5-coder-1.5b-instruct.gguf';
  static const coderSha256 =
      'cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046';
  static const coderApproxBytes = 1117320768;

  /// Platform-appropriate coder filename for fetch + presence checks.
  static String get coder => coderGguf;
}

enum ModelFetchPhase {
  idle,
  ready,
  fetching,
  failed,
}

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

  static ModelPackage get coreChatPackage {
    final name = ModelFetchFiles.chat;
    return ModelPackage(
      id: 'core_chat',
      label: 'Classroom package',
      fileName: name,
      url: '$kModelFetchHfBaseUrl/$name',
      sha256: ModelFetchFiles.chatSha256,
      approxBytes: ModelFetchFiles.chatApproxBytes,
      essential: true,
    );
  }

  static ModelPackage get coreTranslatePackage => const ModelPackage(
        id: 'core_translate',
        label: 'Classroom package',
        fileName: ModelFetchFiles.translate,
        url: '$kModelFetchHfBaseUrl/${ModelFetchFiles.translate}',
        sha256: ModelFetchFiles.translateSha256,
        approxBytes: ModelFetchFiles.translateApproxBytes,
        essential: true,
      );

  static ModelPackage get coderPackage {
    final name = ModelFetchFiles.coder;
    return ModelPackage(
      id: 'coder',
      label: 'Studio package',
      fileName: name,
      url: '$kModelFetchHfBaseUrl/$name',
      sha256: ModelFetchFiles.coderSha256,
      approxBytes: ModelFetchFiles.coderApproxBytes,
      essential: false,
    );
  }

  static List<ModelPackage> get corePackages => [
        coreChatPackage,
        coreTranslatePackage,
      ];

  /// Every package Install Packages pulls in one pass (tutor + translate + coder).
  static List<ModelPackage> get allPackages => [
        ...corePackages,
        coderPackage,
      ];

  /// Canonical install directory (same as USB / manager discovery).
  ///
  /// Android → `<app documents>/models/`
  /// Desktop → `<Documents>/OTIC/`
  Future<Directory> modelsDirectory({bool ensure = true}) async {
    final probe = await canonicalModelInstallPath(
      '_',
      ensureDirectory: ensure,
    );
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
      case 'coder':
        return (await ProgrammingModelManager().checkModel()).isReady;
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

  /// True when tutor + translation + coder are all discoverable.
  Future<bool> areAllPackagesReady() async {
    for (final pkg in allPackages) {
      if (!await isPackagePresent(pkg)) return false;
    }
    return true;
  }

  /// Pre-flight used by the Install Packages screen / ModelGate.
  ///
  /// True when every package (including coder) is already on disk — the UI
  /// must skip the installer and go straight to home.
  Future<bool> checkPackagesCached() => areAllPackagesReady();

  Future<bool> isCoderReady() => isPackagePresent(coderPackage);

  /// Sequential install of **all** packages as a progress stream (white-label).
  ///
  /// Never emits filenames, byte totals for display, or storage paths —
  /// only [ModelFetchUiState] with [fraction] + [statusLabel].
  Stream<ModelFetchUiState> fetchMissingPackages() async* {
    final queue = StreamController<ModelFetchUiState>();
    final done = fetchAllPackages(
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

  /// Fetch tutor + translation + coder in one Install Packages pass.
  /// Skips any file already on disk.
  Future<ModelFetchUiState> fetchAllPackages({
    void Function(ModelFetchUiState state)? onState,
  }) async {
    if (await areAllPackagesReady()) {
      final ready = ModelFetchUiState(
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

    emit(ModelFetchUiState(
      phase: ModelFetchPhase.fetching,
      receivedBytes: received,
      totalBytes: totalBytes,
      statusLabel: whiteLabelStatus(0, connecting: true),
      coderReady: await isCoderReady(),
    ));

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
        await _downloader.download(
          remote,
          targetPath: target,
          cancelToken: token,
          onState: (s) {
            final local = s.receivedBytes;
            final combined = pkgBase + local;
            final frac = totalBytes <= 0 ? 0.0 : combined / totalBytes;
            emit(ModelFetchUiState(
              phase: ModelFetchPhase.fetching,
              receivedBytes: combined,
              totalBytes: totalBytes,
              statusLabel: whiteLabelStatus(
                frac,
                connecting: s.phase == DownloadPhase.connecting,
              ),
              coderReady: false,
            ));
          },
        );
        received = pkgBase + pkg.approxBytes;
      }

      // End-to-end gate: files must be discoverable by the same managers the
      // Windows/Android runtimes use — not merely written to disk.
      if (!await areAllPackagesReady()) {
        throw const ModelDownloadException(
          'Packages downloaded but could not be verified on this device. '
          'Please try Install Packages again.',
        );
      }

      final ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        receivedBytes: totalBytes,
        totalBytes: totalBytes,
        statusLabel: 'Ready',
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

  /// Alias kept for call sites / tests — Install Packages fetches everything.
  Future<ModelFetchUiState> fetchCorePackages({
    void Function(ModelFetchUiState state)? onState,
  }) =>
      fetchAllPackages(onState: onState);

  /// Fallback when coder was deleted after the one-time Install Packages pass.
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
      );
}

final modelFetchServiceProvider = Provider<ModelFetchService>(
  (ref) => ModelFetchService(),
);

/// True when tutor + translation + coder are all on disk (Install Packages done).
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
  }

  void _invalidateCoderStack() {
    _ref.invalidate(programmingModelInfoProvider);
    // Drop stale "coder missing → chat fallback" futures without reloading
    // the chat brain (dualModelRuntime stays warm).
    _ref.invalidate(programmingEngineProvider);
    _ref.invalidate(aiCoderServiceProvider);
  }

  void cancel() => _svc.cancel();
}
