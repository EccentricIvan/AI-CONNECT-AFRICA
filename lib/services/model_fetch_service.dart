import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ai_core/model/model_download_service.dart';
import '../ai_core/model/model_locations.dart';
import '../ai_core/model/model_package.dart';
import '../ai_core/model/model_runtime_policy.dart';
import '../ai_core/providers/ai_provider.dart';

/// Hugging Face `resolve/main` base for classroom packages.
///
/// Replace `YOUR_ORG/otic-models` with the org/repo that hosts the files, or
/// pass
/// `--dart-define=OTIC_HF_MODELS_BASE=https://huggingface.co/.../resolve/main`
/// at build time. No trailing slash.
const kModelFetchHfBaseUrl = String.fromEnvironment(
  'OTIC_HF_MODELS_BASE',
  defaultValue: 'https://huggingface.co/YOUR_ORG/otic-models/resolve/main',
);

/// On-disk names under `<app documents>/models/` (never shown in UI).
class ModelFetchFiles {
  static const chat = 'qwen_brain_0.6b.Q4_K_M.gguf';
  static const translate = 'TranslatePsy-AfriSLM-0.8B.Q4_K_M.gguf';

  /// Android LiteRT brief name (discovery also accepts `.litertlm`).
  static const coderLiteRt = 'qwen_coder_1.5b.literlm';

  /// Windows / Linux llama.cpp GGUF.
  static const coderGguf = 'qwen_coder_1.5b.Q4_K_M.gguf';

  /// Platform-appropriate coder filename for fetch + presence checks.
  static String get coder =>
      useLiteRtCoderRuntime ? coderLiteRt : coderGguf;
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

  static ModelPackage get coreChatPackage => const ModelPackage(
        id: 'core_chat',
        label: 'Classroom package',
        fileName: ModelFetchFiles.chat,
        url: '$kModelFetchHfBaseUrl/${ModelFetchFiles.chat}',
        sha256: '',
        approxBytes: 450 * 1024 * 1024,
        essential: true,
      );

  static ModelPackage get coreTranslatePackage => const ModelPackage(
        id: 'core_translate',
        label: 'Classroom package',
        fileName: ModelFetchFiles.translate,
        url: '$kModelFetchHfBaseUrl/${ModelFetchFiles.translate}',
        sha256: '',
        approxBytes: 520 * 1024 * 1024,
        essential: true,
      );

  static ModelPackage get coderPackage {
    final name = ModelFetchFiles.coder;
    return ModelPackage(
      id: 'coder',
      label: 'Studio package',
      fileName: name,
      url: '$kModelFetchHfBaseUrl/$name',
      sha256: '',
      approxBytes: 1200 * 1024 * 1024,
      essential: false,
    );
  }

  static List<ModelPackage> get corePackages => [
        coreChatPackage,
        coreTranslatePackage,
      ];

  /// Persistent models directory: `<app documents>/models/`.
  Future<Directory> modelsDirectory({bool ensure = true}) async {
    Directory root;
    try {
      root = await getApplicationDocumentsDirectory();
    } catch (_) {
      root = await resolveAppStorageDirectory();
    }
    final dir = Directory(p.join(root.path, 'models'));
    if (ensure) await dir.create(recursive: true);
    return dir;
  }

  Future<String> pathFor(String fileName) async {
    final dir = await modelsDirectory();
    return p.join(dir.path, fileName);
  }

  /// True when [fileName] is already present with a plausible size.
  Future<bool> isPackagePresent(ModelPackage pkg) async {
    final path = await pathFor(pkg.fileName);
    return _fileReady(path, pkg.approxBytes);
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

  Future<bool> isCoderReady() => isPackagePresent(coderPackage);

  /// White-label status line from combined progress (0..1).
  static String whiteLabelStatus(double fraction, {required bool connecting}) {
    if (connecting && fraction <= 0) {
      return 'Initializing offline classroom systems...';
    }
    if (fraction < 0.28) return 'Setting up regional workspace...';
    if (fraction < 0.72) return 'Optimizing formula drivers...';
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

  /// Fetch tutor + translation only. Skips any file already on disk.
  Future<ModelFetchUiState> fetchCorePackages({
    void Function(ModelFetchUiState state)? onState,
  }) async {
    if (await areCorePackagesReady()) {
      final ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        receivedBytes: 1,
        totalBytes: 1,
        coderReady: await isCoderReady(),
      );
      onState?.call(ready);
      return ready;
    }

    final token = CancellationToken();
    _token = token;

    final planned = <ModelPackage>[];
    var alreadyBytes = 0;
    var plannedBytes = 0;
    for (final pkg in corePackages) {
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

      final ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        receivedBytes: totalBytes,
        totalBytes: totalBytes,
        statusLabel: 'Ready',
        coderReady: await isCoderReady(),
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

  /// On-demand coding package. No-op (Ready) if already on disk.
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

    final token = CancellationToken();
    _token = token;
    final pkg =
        coderPackage.copyWith(url: '$hfBaseUrl/${ModelFetchFiles.coder}');
    final total = pkg.approxBytes;

    void emit(ModelFetchUiState s) => onState?.call(s);

    emit(ModelFetchUiState(
      phase: ModelFetchPhase.fetching,
      receivedBytes: 0,
      totalBytes: total,
      statusLabel: whiteLabelCoderStatus(0, connecting: true),
      coderReady: false,
    ));

    try {
      if (await isCoderReady()) {
        const ready = ModelFetchUiState(
          phase: ModelFetchPhase.ready,
          statusLabel: 'Ready',
          receivedBytes: 1,
          totalBytes: 1,
          coderReady: true,
        );
        emit(ready);
        return ready;
      }

      final target = await pathFor(pkg.fileName);
      await _downloader.download(
        pkg,
        targetPath: target,
        cancelToken: token,
        onState: (s) {
          final frac = total <= 0 ? 0.0 : s.receivedBytes / total;
          emit(ModelFetchUiState(
            phase: ModelFetchPhase.fetching,
            receivedBytes: s.receivedBytes,
            totalBytes: s.totalBytes ?? total,
            statusLabel: whiteLabelCoderStatus(
              frac,
              connecting: s.phase == DownloadPhase.connecting,
            ),
            coderReady: false,
          ));
        },
      );

      final ready = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        receivedBytes: total,
        totalBytes: total,
        statusLabel: 'Ready',
        coderReady: true,
      );
      emit(ready);
      return ready;
    } on ModelDownloadException catch (e) {
      final failed = ModelFetchUiState(
        phase: ModelFetchPhase.failed,
        receivedBytes: 0,
        totalBytes: total,
        statusLabel: 'Could not finish setup',
        error: e.message,
        coderReady: false,
      );
      emit(failed);
      return failed;
    } finally {
      _token = null;
    }
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
      final core = await _svc.areCorePackagesReady();
      final coder = await _svc.isCoderReady();
      if (!mounted) return;
      state = ModelFetchUiState(
        phase: core ? ModelFetchPhase.ready : ModelFetchPhase.idle,
        statusLabel: core ? 'Ready' : '',
        receivedBytes: core ? 1 : 0,
        totalBytes: core ? 1 : 0,
        coderReady: coder,
      );
    } catch (e) {
      debugPrint('ModelFetchController refresh: $e');
    }
  }

  Future<void> fetchCore() async {
    if (state.isFetching) return;
    if (await _svc.areCorePackagesReady()) {
      state = ModelFetchUiState(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        receivedBytes: 1,
        totalBytes: 1,
        coderReady: await _svc.isCoderReady(),
      );
      return;
    }

    final result = await _svc.fetchCorePackages(
      onState: (s) {
        if (mounted) state = s;
      },
    );
    if (!mounted) return;
    state = result;
    if (result.isReady) {
      _ref.invalidate(modelInfoProvider);
      _ref.invalidate(translateModelInfoProvider);
    }
  }

  Future<void> fetchCoder() async {
    if (state.isFetching) return;
    if (await _svc.isCoderReady()) {
      state = state.copyWith(
        phase: ModelFetchPhase.ready,
        statusLabel: 'Ready',
        coderReady: true,
      );
      return;
    }

    final result = await _svc.fetchCoderPackage(
      onState: (s) {
        if (mounted) state = s;
      },
    );
    if (!mounted) return;
    state = result;
    if (result.coderReady) {
      _ref.invalidate(programmingModelInfoProvider);
      // Drop stale "coder missing → chat fallback" futures without reloading
      // the chat brain (dualModelRuntime stays warm).
      _ref.invalidate(programmingEngineProvider);
      _ref.invalidate(aiCoderServiceProvider);
    }
  }

  void cancel() => _svc.cancel();
}
