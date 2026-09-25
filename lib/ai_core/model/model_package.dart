/// A model the app can fetch at runtime (Install Packages).
///
/// The models are not bundled into the Play APK: together they blow Play's
/// base-module cap. They ship as separate files and the app pulls them on
/// first run — see `ModelFetchService` for the package list.
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
    this.mirrors = const [],
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

  /// Tried in order when [url] answers 404 (or another hard HTTP error) —
  /// the same bytes elsewhere, e.g. a GitHub release copy while the main
  /// repo is still being filled. [sha256] makes every mirror equally safe.
  final List<String> mirrors;

  /// Whether the app is unusable without it (the brain is; see
  /// `ModelFetchService.corePackages` for how this is used).
  final bool essential;
}
