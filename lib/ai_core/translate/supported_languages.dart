/// The English ↔ African-language pairs TranslatePsy-AfriSLM supports.
///
/// Codes are BCP-47 (matches `Students.language`, students_table.dart).
class SupportedLanguage {
  const SupportedLanguage(this.code, this.name, {String? promptName})
      : _promptName = promptName;

  final String code;

  /// Shown to students in onboarding and Settings.
  final String name;

  final String? _promptName;

  /// The name to put in a translation prompt, which is not always the name
  /// we show. AfriSLM was trained on the language names in its model card,
  /// so a friendlier UI label like "Nyanja (Chichewa)" has to be narrowed
  /// back to "Nyanja" before it reaches the model — naming a language in a
  /// form it never saw is exactly how a 0.8B model ends up guessing.
  String get promptName => _promptName ?? name;
}

/// English plus AfriSLM's Sub-Saharan pairs, and Kirundi (`rn`) which
/// routes through the Kinyarwanda prompt name (no dedicated Kirundi pair).
/// Order matches the model card (huggingface.co/qvac/TranslatePsy-AfriSLM-2B).
const supportedLanguages = <SupportedLanguage>[
  SupportedLanguage('en', 'English'),
  SupportedLanguage('af', 'Afrikaans'),
  SupportedLanguage('am', 'Amharic'),
  SupportedLanguage('ha', 'Hausa'),
  SupportedLanguage('ig', 'Igbo'),
  SupportedLanguage('rw', 'Kinyarwanda'),
  // AfriSLM has no dedicated Kirundi pair. Route through Kinyarwanda
  // (closely related) so the 0.8B model stays on-distribution.
  SupportedLanguage('rn', 'Kirundi', promptName: 'Kinyarwanda'),
  SupportedLanguage('ln', 'Lingala'),
  SupportedLanguage('lg', 'Luganda'),
  SupportedLanguage('mg', 'Malagasy'),
  SupportedLanguage('ny', 'Nyanja (Chichewa)', promptName: 'Nyanja'),
  SupportedLanguage('om', 'Oromo'),
  SupportedLanguage('sn', 'Shona'),
  SupportedLanguage('so', 'Somali'),
  SupportedLanguage('st', 'Southern Sotho'),
  SupportedLanguage('sw', 'Swahili'),
  SupportedLanguage('tn', 'Tswana'),
  SupportedLanguage('wo', 'Wolof'),
  SupportedLanguage('xh', 'Xhosa'),
  SupportedLanguage('yo', 'Yoruba'),
  SupportedLanguage('zu', 'Zulu'),
];

/// Display name for a language code, falling back to the code itself for
/// anything outside the supported list (defensive — shouldn't happen since
/// onboarding/Settings only ever write codes from [supportedLanguages]).
String languageName(String code) {
  for (final lang in supportedLanguages) {
    if (lang.code == code) return lang.name;
  }
  return code;
}

/// Language name to use inside a translation prompt. Falls back to the code
/// for anything outside the supported list.
String languagePromptName(String code) {
  for (final lang in supportedLanguages) {
    if (lang.code == code) return lang.promptName;
  }
  return code;
}

/// Codes offered in the onboarding/Settings language picker. AfriSLM still
/// supports the full [supportedLanguages] list underneath (translation,
/// voice, UI chrome all keep working for any of them), but only these show
/// up as choices — narrowing what's *pickable* without dropping support for
/// a code a student may already have saved.
const _pickableLanguageCodes = {'en', 'lg', 'sw', 'rw', 'ln'};

/// The subset of [supportedLanguages] to show in language pickers.
final pickableLanguages = supportedLanguages
    .where((lang) => _pickableLanguageCodes.contains(lang.code))
    .toList();

/// True for English plus every AfriSLM pair (and Kirundi → Kinyarwanda).
bool isSupportedLearningLanguage(String code) {
  for (final lang in supportedLanguages) {
    if (lang.code == code) return true;
  }
  return false;
}

/// Session override, then the student profile, then the on-disk preference.
/// Prefs cover guests and the first launch after downloading the app.
String resolveLearningLanguage({
  String? override,
  String? persisted,
  String? studentLanguage,
}) {
  for (final code in [override, studentLanguage, persisted]) {
    if (code != null &&
        code.isNotEmpty &&
        isSupportedLearningLanguage(code)) {
      return code;
    }
  }
  return 'en';
}
