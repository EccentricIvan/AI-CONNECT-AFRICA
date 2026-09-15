library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'engine_scheduler.dart';

const int kLlamaContextSize = 2048;

/// AfriSLM prompts are short (clause / sentence). A smaller KV keeps the
/// translator loadable beside LiteRT on 4 GB Android devices after
/// Install Packages.
const int kLlamaTranslateContextSize = 1024;
const int kLlamaTranslateBatchSize = 512;

/// Prefill batch must cover the tokenized chat template (system + user).
///
/// At 512, the hybrid Africa AI Connect contract + curriculum notes already
/// hit ~560 tokens and tripped `GGML_ASSERT(n_tokens_all <= n_batch)`, which
/// aborts the Windows process ("Lost connection to device") — often on the
/// second turn once THREAD history is appended. 1024 leaves headroom while
/// staying under [kLlamaContextSize].
const int kLlamaBatchSize = 1024;

/// Soft char budget for system+user before tokenization (~3 chars/token).
/// See [fitLlamaChatBodies] in prompt_budget.dart — native assert guard.
const int kLlamaSafePromptChars = (kLlamaBatchSize - 128) * 3;

/// CPU-only baseline. Prefer [llamaGpuLayersForLane] so reason/program
/// engines can use Vulkan when the linked ggml already requires it to load.
const int kLlamaGpuLayers = 0;

/// Offload as many transformer layers as VRAM allows (llama.cpp `99` /
/// `-1` style). Desktop ggml is Vulkan-linked — when the engine loads at
/// all, GPU offload is usually available and much faster than CPU decode.
/// Keep the translator on CPU so two mapped GGUFs do not fight for the
/// same VRAM on school laptops.
const int kLlamaGpuLayersAccelDesktop = 99;

/// On Android, dual GGUFs + GPU can OOM mid-session. Stay on CPU unless
/// we later measure a safe layer count per device class.
const int kLlamaGpuLayersAccelMobile = 0;

bool get kLlamaOnDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// GPU layers for one llama.cpp engine role.
int llamaGpuLayersForLane(String lane) {
  if (lane == EngineLane.translate) return kLlamaGpuLayers;
  return kLlamaOnDesktop
      ? kLlamaGpuLayersAccelDesktop
      : kLlamaGpuLayersAccelMobile;
}

/// Thread count for llama.cpp. Auto (`null`) often oversubscribes
/// hyperthreads on Windows and slows decode; physical-ish cores capped
/// at 8 is a better default for school CPUs.
int? get kLlamaThreads {
  if (kIsWeb) return null;
  try {
    final n = Platform.numberOfProcessors;
    if (n <= 2) return n;
    return (n ~/ 2).clamp(2, 8);
  } catch (_) {
    return null;
  }
}
