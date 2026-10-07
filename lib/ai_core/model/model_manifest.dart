import 'package:path/path.dart' as p;

/// What a model can be asked to do.
enum ModelCapability { chat, code, reasoning, translate }

/// The runtime that loads a model file — one per platform
/// (see model_runtime_policy.dart).
enum ModelRuntime { liteRtLm, llamaCpp }

/// What the app knows about one model file before loading it: what it can
/// do, which runtime loads it, and the SHA-256 its release was published
/// with. The app asks the registry for a capability, not for a model by
/// name.
class ModelManifest {
  const ModelManifest({
    required this.id,
    required this.version,
    required this.fileName,
    required this.runtime,
    required this.quantization,
    required this.capabilities,
    required this.sha256,
    required this.approxBytes,
    required this.license,
    this.languages = const ['en'],
    this.contextLength,
  });

  final String id;
  final String version;
  final String fileName;
  final ModelRuntime runtime;
  final String quantization;
  final Set<ModelCapability> capabilities;

  /// BCP-47 codes it reads and writes.
  final List<String> languages;

  /// Tokens, when the model card states it.
  final int? contextLength;

  /// Lower-case hex, as CI publishes it.
  final String sha256;
  final int approxBytes;
  final String license;
}

const _afrislmLanguages = [
  'en', 'af', 'am', 'ha', 'ig', 'rw', 'rn', 'ln', 'lg', 'mg', 'ny', 'om', //
  'sn', 'so', 'st', 'sw', 'tn', 'wo', 'xh', 'yo', 'zu',
];

const kBrainGguf = ModelManifest(
  id: 'qwen2.5-coder-1.5b-instruct',
  version: 'q4_k_m',
  fileName: 'qwen2.5-coder-1.5b-instruct.gguf',
  runtime: ModelRuntime.llamaCpp,
  quantization: 'Q4_K_M',
  capabilities: {
    ModelCapability.chat,
    ModelCapability.code,
    ModelCapability.reasoning,
  },
  contextLength: 32768,
  sha256: 'cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046',
  approxBytes: 1117320768,
  license: 'Apache-2.0',
);

const kBrainLiteRt = ModelManifest(
  id: 'qwen2.5-coder-1.5b-instruct',
  version: 'int4',
  fileName: 'qwen2.5-coder-1.5b-instruct_int4.litertlm',
  runtime: ModelRuntime.liteRtLm,
  quantization: 'int4',
  capabilities: {
    ModelCapability.chat,
    ModelCapability.code,
    ModelCapability.reasoning,
  },
  contextLength: 32768,
  sha256: '273ecc7771ba2dd5fe1bb6d4d4726ad0353102f04ad094082ccf59bca9f21213',
  approxBytes: 1117385648,
  license: 'Apache-2.0',
);

const kTranslatorGguf = ModelManifest(
  id: 'translatepsy-afrislm-0.8b',
  version: 'q4_k_m',
  fileName: 'afrislm-0.8b-q4_k_m.gguf',
  runtime: ModelRuntime.llamaCpp,
  quantization: 'Q4_K_M',
  capabilities: {ModelCapability.translate},
  languages: _afrislmLanguages,
  sha256: '4af8ee1df3ec9008f763ebe95e6f21df3acd8d42c541feeb13314ca22e560afc',
  approxBytes: 672329792,
  license: 'Apache-2.0',
);

const kTranslatorLiteRt = ModelManifest(
  id: 'translatepsy-afrislm-0.8b',
  version: 'int8',
  fileName: 'afrislm-0.8b_int8.litertlm',
  runtime: ModelRuntime.liteRtLm,
  quantization: 'int8',
  capabilities: {ModelCapability.translate},
  languages: _afrislmLanguages,
  sha256: 'f5a356714430f7174f970411148601118e38dc5a7b524ff920d3d0bef122579a',
  approxBytes: 898256944,
  license: 'Apache-2.0',
);

/// Every model file this build knows.
const kModelManifests = [
  kBrainGguf,
  kBrainLiteRt,
  kTranslatorGguf,
  kTranslatorLiteRt,
];

class ModelRegistry {
  const ModelRegistry([this.manifests = kModelManifests]);

  final List<ModelManifest> manifests;

  /// The manifest for a file at [path], by its name; null for a file this
  /// build doesn't know (an alternative name a teacher copied in).
  ModelManifest? forFile(String path) {
    final name = p.basename(path).toLowerCase();
    for (final m in manifests) {
      if (m.fileName.toLowerCase() == name) return m;
    }
    return null;
  }

  /// Models on [runtime] that can do [capability] — in [language], when
  /// given.
  List<ModelManifest> forCapability(
    ModelCapability capability, {
    required ModelRuntime runtime,
    String? language,
  }) => [
    for (final m in manifests)
      if (m.runtime == runtime &&
          m.capabilities.contains(capability) &&
          (language == null || m.languages.contains(language)))
        m,
  ];
}
