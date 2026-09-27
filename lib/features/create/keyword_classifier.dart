/// Picks the entry whose keywords best match [text]: each matched keyword
/// scores its length, highest total wins, [fallback] when nothing matches.
///
/// Summing matches instead of taking the first hit means "a shop till for my
/// store" resolves to the till, not the shop, whatever order entries are in.
/// Keywords match from a word start; ones of three letters or fewer must be
/// the whole word, so "pos" doesn't fire on "purpose" or "spa" on "space".
T classifyByKeywords<T>(
  String text,
  List<T> entries,
  List<String> Function(T entry) keywordsOf,
  T fallback,
) {
  final lower = text.toLowerCase();
  T? best;
  var bestScore = 0;
  for (final entry in entries) {
    var score = 0;
    for (final keyword in keywordsOf(entry)) {
      if (mentionsKeyword(lower, keyword)) score += keyword.length;
    }
    if (score > bestScore) {
      bestScore = score;
      best = entry;
    }
  }
  return best ?? fallback;
}

bool mentionsKeyword(String lowerText, String keyword) {
  final escaped = RegExp.escape(keyword.toLowerCase());
  final pattern = keyword.length <= 3 ? '\\b$escaped\\b' : '\\b$escaped';
  return RegExp(pattern).hasMatch(lowerText);
}
