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

/// Greedy-leaning decode. Chat brain locks to [kChatTemperature] (0.0).
const double kTutorTemperature = 0.0;

/// Deterministic chat/tutor sampling — argmax, no prefill noise.
const double kChatTemperature = 0.0;

/// AfriSLM model-card setting — same greedy path.
const double kTranslateTemperature = 0.1;

/// Coder builds use a near-greedy decode (Android LiteRT / Windows GGUF).
const double kCoderTemperature = 0.0;

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
/// Enough room for a full mentor beat even if a few think tokens leak first.
const int kMaxNewTokens = 350;

/// Coding replies need room for a short fenced snippet plus the explanation.
const int kProgrammingMaxTokens = 400;

/// One-shot website Build from recorded features (1.5B coder).
/// Compact page — enough for a small site without multi-minute CPU decode.
const int kSiteBuildMaxTokens = 1100;

/// One-shot mobile-web app Build from recorded features (1.5B coder).
const int kAppBuildMaxTokens = 650;

/// Lab "Autocorrect" polish via the 1.5B coder (short snippets).
const int kCodeFixMaxTokens = 500;

/// Forward English into AfriSLM at this many characters if no punctuation.
const int kTranslateFlushChars = 50;

/// Coder UI stream flush: clause end (`.?!\\n`) or this many pending chars.
const int kCoderStreamFlushChars = 60;

/// Tutor turns stay short; site/app coder briefs need the full feature lock.
const int kTutorMaxPromptChars = 1600;

/// Upper bound for LiteRT coder / system-prompted one-shots (HTML, schema).
const int kCoderMaxPromptChars = 6000;
