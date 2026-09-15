import 'supported_languages.dart';

/// Languages the chat picker and dual-model cascade are built for.
///
/// English is the reasoning language. AfriSLM handles Luganda, Swahili,
/// Kinyarwanda, Somali, and Lingala. Each code is a distinct AfriSLM pair.
const kPrimaryChatLanguages = ['en', 'lg', 'sw', 'rw', 'so', 'ln'];

bool isPrimaryChatLanguage(String code) =>
    kPrimaryChatLanguages.contains(code);

/// Picker entries, in the order students see them.
final chatLanguages = [
  for (final code in kPrimaryChatLanguages)
    supportedLanguages.firstWhere((l) => l.code == code),
];

/// Map a stored / legacy code onto a picker value so dropdowns never crash.
///
/// Every AfriSLM language stays itself. Only unknown codes fall back to
/// English — mapping Yoruba / Zulu / … to `en` made local-language chat
/// look broken after a download if the saved profile was not in the
/// short East-Africa picker list.
String coerceChatLanguage(String code) {
  if (isPrimaryChatLanguage(code)) return code;
  if (code == 'rn') return 'rw';
  if (isSupportedLearningLanguage(code)) return code;
  return 'en';
}

/// AfriSLM model-card language name for a chat turn.
String chatTranslatePromptName(String code) {
  switch (code) {
    case 'lg':
      return 'Luganda';
    case 'rw':
      return 'Kinyarwanda';
    case 'sw':
      return 'Swahili';
    case 'so':
      return 'Somali';
    case 'ln':
      return 'Lingala';
    case 'en':
      return 'English';
    default:
      return languagePromptName(code);
  }
}

/// Extra style hint for the AfriSLM system prompt. Null for English.
String? chatTranslateStyle(String languageName) {
  switch (languageName) {
    case 'Luganda':
      return 'Use natural Luganda school language. Keep names and formulas unchanged.';
    case 'Kinyarwanda':
      return 'Use natural Kinyarwanda school language. Keep names and formulas unchanged.';
    case 'Swahili':
      return 'Use natural Kiswahili school language. Keep names and formulas unchanged.';
    case 'Somali':
      return 'Use natural Somali school language. Keep names and formulas unchanged.';
    case 'Lingala':
      return 'Use natural Lingala school language. Keep names and formulas unchanged.';
    default:
      return null;
  }
}
