library;

import 'package:flutter/foundation.dart';

const int kLlamaContextSize = 2048;
const int kLlamaBatchSize = 256;

/// CPU-only. See [LlamaCppEngineImpl] watchdog copy about Vulkan.
const int kLlamaGpuLayers = 0;

bool get kLlamaOnDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
