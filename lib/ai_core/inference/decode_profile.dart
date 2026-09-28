/// Which way the brain decodes a call.
///
/// Everything decodes greedily by default (`kTopK` 1), which keeps code
/// builds, CSS patches and JSON generators exact and repeatable. Greedy
/// decoding on a 1.5B model is also what makes a tutor answer fall into a
/// loop — writing one paragraph over and over. So the two paths that fill
/// the chat bubble (the tutor and the chat service) run inside
/// [runAsProse], and the engines then:
///
///   * sample lightly — [kProseTemperature], [kProseTopK], [kProseTopP],
///     with a fixed seed so the same question still gets the same answer;
///   * add [kProseRepeatPenalty] where the runtime supports one (llama.cpp —
///     LiteRT-LM has no penalty knob);
///   * put the stream through `RepetitionGuard`, which stops a loop the
///     sampling didn't prevent.
///
/// A zone value rather than a `generate` parameter: the engine interface
/// has many implementations, and only these two callers need to say it.
library;

import 'dart:async';

const double kProseTemperature = 0.3;
const int kProseTopK = 20;
const double kProseTopP = 0.8;

/// Qwen2.5's own generation_config value — mild, so it discourages loops
/// without warping word choice.
const double kProseRepeatPenalty = 1.05;

final Object _proseKey = Object();

/// Runs [body] so the engine calls it makes decode as prose.
R runAsProse<R>(R Function() body) =>
    runZoned(body, zoneValues: {_proseKey: true});

/// True inside [runAsProse]. Engines read it at the start of `generate`.
bool get isProseDecode => Zone.current[_proseKey] == true;
