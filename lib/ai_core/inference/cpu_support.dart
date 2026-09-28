/// Whether this machine's CPU can run the bundled llama.cpp engine.
///
/// llm_llamacpp's prebuilt x64 binaries are compiled for AVX2. On a CPU
/// without it (budget Celeron / Pentium Silver, older chips) the first
/// decode executes an AVX instruction and Windows ends the whole process
/// with STATUS_ILLEGAL_INSTRUCTION (0xC000001D) — no Dart exception, the
/// app just closes. Check [cpuSupportsLlamaCpp] before loading a GGUF.
library;

export 'cpu_support_stub.dart'
    if (dart.library.ffi) 'cpu_support_native.dart';
