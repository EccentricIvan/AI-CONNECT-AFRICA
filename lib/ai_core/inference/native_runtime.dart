/// Embedded inference FFI — llama.cpp (Qwen + AfriSLM GGUF).
///
/// Decode runs in llm_llamacpp's persistent isolate. Lanes:
/// [EngineLane.reason] vs [EngineLane.translate].
library;

export 'engine_scheduler.dart';
export 'localized_generate.dart';
export 'pinned_prompt_cache.dart';
export 'runtime_config.dart';
export 'stream_cascade.dart';
