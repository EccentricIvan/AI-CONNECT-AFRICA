/// Instant local → English for short follow-ups.
///
/// AfriSLM is the general translator, but "why" / "yes" / "explain more"
/// are the turns that [ConversationMemory] must keep on the last topic.
/// A glossary lookup is free and stable; the 0.8B model is neither, and
/// skipping it on these phrases also drops a second of latency.
String? toEnglishFollowUp(String text, {String? langCode}) {
  final t = normalizeFollowUp(text);
  if (t.isEmpty) return null;
  if (_englishShort.contains(t)) return t;
  if (langCode != null && langCode.isNotEmpty && langCode != 'en') {
    return _byLang[langCode]?[t];
  }
  for (final map in _byLang.values) {
    final hit = map[t];
    if (hit != null) return hit;
  }
  return null;
}

String normalizeFollowUp(String text) {
  return text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[?.!،؟]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

const _englishShort = {
  'why',
  'how',
  'yes',
  'yeah',
  'yep',
  'ok',
  'okay',
  'sure',
  'no',
  'more',
  'example',
  'an example',
  'explain more',
  'continue',
  'go on',
  'next',
};

/// Luganda, Kinyarwanda, Kirundi, Lingala, Swahili — the learning languages
/// this product answers curriculum questions in (plus English, which needs
/// no map).
const _byLang = <String, Map<String, String>>{
  'lg': {
    'lwaki': 'why',
    'ntya': 'how',
    'yee': 'yes',
    'weewawo': 'yes',
    'kale': 'ok',
    'kati': 'ok',
    'nedda': 'no',
    'nnyonnyola': 'explain more',
    'nnyonnyola nnyo': 'explain more',
    'tegeera': 'explain more',
    'sitegedde': "i don't understand",
    'simtegedde': "i don't understand",
    'nntegedde': 'yes',
    'ekyokulabirako': 'example',
    'kyokulabirako': 'example',
    'weeyongere': 'continue',
    'genda mu maaso': 'continue',
    'nnyo': 'more',
    'endala': 'more',
    'ate': 'what about that',
  },
  'sw': {
    'kwa nini': 'why',
    'kwanini': 'why',
    'vipi': 'how',
    'namna gani': 'how',
    'ndiyo': 'yes',
    'ndio': 'yes',
    'sawa': 'ok',
    'hapana': 'no',
    'eleza zaidi': 'explain more',
    'eleza tena': 'explain more',
    'sielewi': "i don't understand",
    'mfano': 'example',
    'toan mfano': 'example',
    'endelea': 'continue',
    'zaidi': 'more',
    'nini kuhusu hiyo': 'what about that',
  },
  'rw': {
    'kuki': 'why',
    'kubera iki': 'why',
    'gute': 'how',
    'yego': 'yes',
    'nika': 'ok',
    'nibyo': 'ok',
    'oya': 'no',
    'sobanura': 'explain more',
    'nsobanurire': 'explain more',
    'sobanura neza': 'explain more',
    'sinyumva': "i don't understand",
    'ntabyumva': "i don't understand",
    'urugero': 'example',
    'komeza': 'continue',
    'byinshi': 'more',
    'iki cyane': 'what about that',
  },
  'rn': {
    'kuki': 'why',
    'kubera iki': 'why',
    'gute': 'how',
    'ego': 'yes',
    'yego': 'yes',
    'nika': 'ok',
    'oya': 'no',
    'sobanura': 'explain more',
    'nsobanurire': 'explain more',
    'sinumva': "i don't understand",
    'sinyumva': "i don't understand",
    'urugero': 'example',
    'komeza': 'continue',
    'vyinshi': 'more',
    'ivyo': 'what about that',
  },
  'ln': {
    'mpo na nini': 'why',
    'mpo nini': 'why',
    'ndenge nini': 'how',
    'nini': 'how',
    'iyo': 'yes',
    'ee': 'yes',
    'malamu': 'ok',
    'te': 'no',
    'limbola lisusu': 'explain more',
    'limbola': 'explain more',
    'nazongi te': "i don't understand",
    'na yoka te': "i don't understand",
    'nayoka te': "i don't understand",
    'ndakisa': 'example',
    'koba': 'continue',
    'mingi': 'more',
    'nini na yango': 'what about that',
  },
};
