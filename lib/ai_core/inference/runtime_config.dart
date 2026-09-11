/// On-device dual-SLM budget and generation knobs.
///
/// Both engines stay mapped, not copied:
///   * Reasoning — Qwen-0.6B-Instruct GGUF via llama.cpp
///   * Translation — TranslatePsy-AfriSLM 0.8B GGUF via llama.cpp
///
/// Decode is greedy: [kTutorTemperature] 0.1, [kDoSample] false, [kTopK] 1
/// so the sampler skips nucleus graphs. Qwen's conversational KV is English
/// only. AfriSLM never stores tutor history.
library;

/// Greedy-leaning decode. `0.1` with [kTopK] = 1 is effectively argmax.
const double kTutorTemperature = 0.1;

/// AfriSLM model-card setting — same greedy path.
const double kTranslateTemperature = 0.1;

/// Hardcoded `do_sample: false`. llama.cpp has no separate flag; top-k 1
/// plus this temperature is the equivalent.
const bool kDoSample = false;

/// Nucleus disabled — the full distribution is unused because [kTopK] is 1.
const double kTopP = 1.0;

/// Greedy: consider only the argmax token.
const int kTopK = 1;

/// Fixed seed so two identical prompts decode the same way.
const int kRandomSeed = 0;

/// Hard cap on tutor decode length (0.6B general reasoning).
const int kMaxNewTokens = 150;

/// Coding replies need room for a short fenced snippet plus the explanation.
const int kProgrammingMaxTokens = 400;

/// Forward English into AfriSLM at this many characters if no punctuation.
const int kTranslateFlushChars = 50;
