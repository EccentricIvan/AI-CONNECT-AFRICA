library;

import 'package:flutter/foundation.dart';

const int kLlamaContextSize = 2048;

/// Must cover the tokenized tutor prompt (often ~350 tokens). 256 crashed
/// with `n_tokens_all <= n_batch`. Keep this below context size so Windows
/// debug builds do not OOM while Qwen + AfriSLM stay mapped.
const int kLlamaBatchSize = 512;

/// CPU-only. See [LlamaCppEngineImpl] watchdog copy about Vulkan.
const int kLlamaGpuLayers = 0;

bool get kLlamaOnDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
