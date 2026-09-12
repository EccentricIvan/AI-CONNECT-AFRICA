import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/language_provider.dart';

/// Chrome label: uses the student's selected language tables.
String devTr(BuildContext context, String english) => tr(context, english);

Future<String> _activeLang(WidgetRef ref) async {
  final override = ref.read(languageOverrideProvider);
  if (override != null) return override;
  try {
    final student = await ref.read(activeStudentProvider.future);
    return student?.language ?? 'en';
  } catch (_) {
    return 'en';
  }
}

/// Bot copy for Create / site / app builders.
///
/// Prefers canned UI strings when present; otherwise AfriSLM English → local.
Future<String> localizeDevBot(WidgetRef ref, String english) async {
  final lang = await _activeLang(ref);
  if (lang == 'en' || english.trim().isEmpty) return english;
  final canned = uiString(lang, english);
  if (canned != null) return canned;
  try {
    final pipeline = await ref.read(translationPipelineProvider.future);
    if (pipeline == null) return english;
    return await pipeline.fromEnglish(english, lang);
  } catch (_) {
    return english;
  }
}

/// Student typed local language → English for matching / coder briefs.
Future<String> localizeDevStudent(WidgetRef ref, String typed) async {
  final lang = await _activeLang(ref);
  if (lang == 'en' || typed.trim().isEmpty) return typed;
  try {
    final pipeline = await ref.read(translationPipelineProvider.future);
    if (pipeline == null) return typed;
    return await pipeline.toEnglish(typed, lang);
  } catch (_) {
    return typed;
  }
}
