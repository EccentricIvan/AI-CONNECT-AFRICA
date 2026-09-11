import 'package:flutter/widgets.dart';

import 'ui_strings.dart';
import 'ui_strings_curriculum.dart';
import 'ui_strings_generated.dart';
import 'ui_strings_more.dart';

class AppLocale extends InheritedWidget {
  const AppLocale({super.key, required this.languageCode, required super.child});

  final String languageCode;

  static String of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppLocale>()?.languageCode ??
        'en';
  }

  @override
  bool updateShouldNotify(AppLocale oldWidget) =>
      languageCode != oldWidget.languageCode;
}

/// Exact chrome lookup. Null when [code] has no row for [english].
///
/// Tutor replies are not stored here — AfriSLM generates those.
String? uiString(String code, String english) {
  if (code == 'en') return english;
  return kUiStrings[code]?[english] ??
      kUiStringsMore[code]?[english] ??
      kUiStringsCurriculum[code]?[english] ??
      kUiStringsGenerated[code]?[english];
}

/// Looks up a UI string. [english] is both the key and the English fallback.
String tr(BuildContext context, String english) {
  final code = AppLocale.of(context);
  return uiString(code, english) ?? english;
}

/// True when [english] has a real chrome entry for [code].
///
/// Lets chat skip AfriSLM for buttons and stage follow-ups that already
/// live in the UI tables, without treating tutor teaching as canned text.
bool hasUiString(String code, String english) {
  if (code == 'en') return true;
  return kUiStrings[code]?[english] != null ||
      kUiStringsMore[code]?[english] != null ||
      kUiStringsCurriculum[code]?[english] != null ||
      kUiStringsGenerated[code]?[english] != null;
}

String trFill(BuildContext context, String english, Map<String, String> vars) {
  var out = tr(context, english);
  vars.forEach((k, v) => out = out.replaceAll('{$k}', v));
  return out;
}
