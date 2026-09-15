import 'model_manager.dart';

/// A model the app can fetch at runtime from the `model-pack` release.
///
/// The models are no longer bundled into the APK: at ~1.2 GB together they
/// blow Play's 500 MB base-module cap on their own. They ship as separate
/// release assets instead, and the app pulls them on first run.
///
/// [sha256] is checked on-device after the bytes land. It is the same hash
/// CI verifies when publishing the release, so a truncated download, a
/// corrupted SD card, or a hijacked mirror all fail closed rather than
/// handing a broken file to llama.cpp.
class ModelPackage {
  const ModelPackage({
    required this.id,
    required this.label,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.approxBytes,
    required this.essential,
  });

  final String id;

  /// Shown on the download button.
  final String label;
  final String fileName;
  final String url;
  final String sha256;

  /// For the storage precheck and the "how big is this" line in the UI.
  /// The real size comes from the response, this only has to be close.
  final int approxBytes;

  /// Chat is essential — without it there is no tutor. Translation is not:
  /// the app works in English while it is missing, so it is a separate
  /// download the user can defer. On metered data that split matters.
  final bool essential;

  static const _base =
      'https://github.com/EccentricIvan/otic-studio-v3/releases/download/model-pack';

  static const chat = ModelPackage(
    id: 'chat',
    label: 'Tutor model',
    fileName: ModelManager.chatModelFileName,
    url: '$_base/${ModelManager.chatModelFileName}',
    sha256: '555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4',
    approxBytes: 586 * 1024 * 1024,
    essential: true,
  );

  /// GitHub `model-pack` ships `translate-afrislm.gguf` (discovered via
  /// [AfriSlmModelManager.alternateFileNames]). Install Packages uses the
  /// HF Q4 filename from [ModelFetchFiles.translate] instead.
  static const translate = ModelPackage(
    id: 'translate',
    label: 'Translation model',
    fileName: 'translate-afrislm.gguf',
    url: '$_base/translate-afrislm.gguf',
    sha256: '4af8ee1df3ec9008f763ebe95e6f21df3acd8d42c541feeb13314ca22e560afc',
    approxBytes: 642 * 1024 * 1024,
    essential: false,
  );

  static const all = <ModelPackage>[chat, translate];
}
