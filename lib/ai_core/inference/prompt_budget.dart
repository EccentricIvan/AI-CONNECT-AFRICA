import 'native_ffi_config.dart';

/// Chat-template / role-tag overhead outside system+user body text.
const int kLlamaTemplateOverheadChars = 280;

/// Chars→tokens budget ratio. Qwen English often ~4 chars/token; use 3 so
/// we stay under [kLlamaBatchSize] with margin for denser markup.
const int kLlamaCharsPerTokenBudget = 3;

/// Soft char budget for the tokenized prefill (system + user + template).
int get kLlamaPrefillCharBudget =>
    (kLlamaBatchSize - 128) * kLlamaCharsPerTokenBudget;

/// Fit system + user bodies so tokenized prefill stays under [kLlamaBatchSize].
///
/// Prefer keeping the end of [user] (CURRENT question). Shrink [system] only
/// when it alone crowds out a usable user turn.
({String? system, String user}) fitLlamaChatBodies({
  String? system,
  required String user,
  int overheadChars = kLlamaTemplateOverheadChars,
  int prefillCharBudget = -1,
}) {
  final budget =
      prefillCharBudget < 0 ? kLlamaPrefillCharBudget : prefillCharBudget;
  final usable = budget - overheadChars;
  if (usable < 200) {
    return (
      system: null,
      user: _tail(user, 180),
    );
  }

  var sys = system?.trim();
  if (sys != null && sys.isEmpty) sys = null;

  const minUser = 200;
  final maxSys = usable - minUser;
  if (sys != null && sys.length > maxSys) {
    sys = '${sys.substring(0, maxSys - 1)}…';
  }

  final sysLen = sys?.length ?? 0;
  final userBudget = usable - sysLen;
  if (user.length <= userBudget) {
    return (system: sys, user: user);
  }
  const prefix = '…\n';
  final keep = userBudget > prefix.length
      ? userBudget - prefix.length
      : userBudget;
  return (system: sys, user: '$prefix${_tail(user, keep)}');
}

String _tail(String text, int maxChars) {
  if (maxChars <= 0) return '';
  if (text.length <= maxChars) return text;
  return text.substring(text.length - maxChars);
}
