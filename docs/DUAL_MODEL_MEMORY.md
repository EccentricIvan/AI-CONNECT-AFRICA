# Dual-model memory budget (≤ 1.2 GB RAM)

On-device stack, not PyTorch:

| Role | Runtime (FFI) | File | Disk |
|------|----------------|------|------|
| Chat / tutor | LiteRT-LM (`flutter_gemma_litertlm`) | `chat-model.litertlm` | ~330–590 MB |
| Translation | llama.cpp (`llm_llamacpp`) | `translate-afrislm.gguf` | ~500–650 MB |

**Why resident RAM stays under 1.2 GB**

1. Both files are memory-mapped. The OS keeps one copy; pages fault in as decode needs them.
2. **Sequential swap on Android.** [EngineScheduler] lets only AfriSLM `generate` hold the exclusive lock. Qwen's Dart `await for` awaits each flushed clause through AfriSLM, so LiteRT stops pulling tokens while the GGUF is mapped, decoded, and freed. Desktop pipelines Qwen decode with the llama.cpp isolate ([NativeOverlapPolicy.pipelined]).
3. Tutor decode is capped at 150 new tokens. Both models decode greedily (`temperature: 0.0`, `do_sample: false`, `top_p: 1.0`, `top_k: 1`).
4. Outbound translation consumes **clauses** (punctuation / newline / 60 characters), not a second full English buffer plus a finished paragraph.
5. The tutor contract is pinned once via LiteRT `createChat(systemInstruction:)`. AfriSLM system prompts are interned; the Drift cache skips a GGUF reload when the same clause has already been translated. llama.cpp still frees the GGUF after each request, so a native prefix-KV cannot survive across calls.
6. AWQ folders under `assets/models/*_4bit` are workstation artifacts. They are not loaded next to the mapped GGUF/LiteRT files.

If a third runtime (PyTorch, a second ONNX session) is added beside these two, the 1.2 GB ceiling is lost.
