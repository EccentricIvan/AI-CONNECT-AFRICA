import 'package:flutter/material.dart';

/// Catalog entry for App Dev Lab feature picking.
class AppLabType {
  const AppLabType({
    required this.id,
    required this.name,
    required this.icon,
    required this.featureOptions,
  });

  final String id;
  final String name;
  final IconData icon;
  final List<String> featureOptions;
}

class AppLabTheme {
  const AppLabTheme({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryHex,
    required this.background,
    required this.surface,
    required this.onPrimary,
  });

  final String id;
  final String name;
  final Color primary;
  final String primaryHex;
  final Color background;
  final Color surface;
  final Color onPrimary;
}

/// Locked feature block passed into the Build pipeline.
class AppBuildIntent {
  AppBuildIntent({
    required this.appTypeId,
    required this.appTypeName,
    required this.themeId,
    required this.themeName,
    required this.themePrimary,
    required this.answers,
    required this.features,
  });

  final String appTypeId;
  final String appTypeName;
  final String themeId;
  final String themeName;
  final String themePrimary;
  final Map<String, String> answers;
  final List<String> features;

  String get appName {
    final n = answers['app_name']?.trim();
    if (n != null && n.isNotEmpty) return n;
    return appTypeName;
  }

  String get purpose => answers['purpose']?.trim() ?? '';

  String get audience => answers['audience']?.trim() ?? '';

  /// Brief for the on-device 1.5B coder (declarative UI schema target).
  String toUiSchemaBrief() {
    final buf = StringBuffer()
      ..writeln('/no_think')
      ..writeln(
        'Output ONLY an OTIC_UI_V1 declarative UI schema for a student app.',
      )
      ..writeln('No markdown fences. No commentary. No Dart. No HTML.')
      ..writeln('First lines:')
      ..writeln('OTIC_UI_V1')
      ..writeln('title: <app name>')
      ..writeln('style: <theme name>')
      ..writeln('Then one element per line using this exact shape:')
      ..writeln('Type: Header, Text: ...')
      ..writeln('Type: Text, Text: ...')
      ..writeln('Type: TextField, Label: ..., Hint: ...')
      ..writeln('Type: Button, Text: ..., Action: Alert, Style: Cyberpunk')
      ..writeln('Type: Chip, Text: ...')
      ..writeln('Type: Card, Title: ..., Text: ...')
      ..writeln('Type: List, Items: a|b|c')
      ..writeln()
      ..writeln('APP TYPE: $appTypeName ($appTypeId)')
      ..writeln('VISUAL STYLE: $themeName — primary $themePrimary');

    if (answers.isNotEmpty) {
      buf.writeln();
      buf.writeln('STUDENT DETAILS:');
      for (final e in answers.entries) {
        if (e.value.trim().isEmpty) continue;
        buf.writeln('- ${e.key}: ${e.value}');
      }
    }
    if (features.isNotEmpty) {
      buf.writeln();
      buf.writeln('SELECTED FEATURES (must appear as Chip or Card lines):');
      for (final f in features) {
        buf.writeln('- $f');
      }
    }
    buf
      ..writeln()
      ..writeln('Include a Header with the app name and a Save Button.');
    return buf.toString();
  }

  /// Brief for the on-device 1.5B coder (Dart widget target).
  String toCoderBrief() {
    final buf = StringBuffer()
      ..writeln('/no_think')
      ..writeln(
        'Write one complete Flutter Dart file: a single StatefulWidget '
        'named StudentApp with inline widgets and local state only.',
      )
      ..writeln(
        'Output ONLY Dart source. No markdown fences. No commentary. '
        'No thinking. Start with imports or the class.',
      )
      ..writeln(
        'Use material.dart only. Keep it short and beautiful. '
        'Phone-sized layout (max width ~420).',
      )
      ..writeln()
      ..writeln('APP TYPE: $appTypeName ($appTypeId)')
      ..writeln('VISUAL STYLE: $themeName — primary $themePrimary');

    if (answers.isNotEmpty) {
      buf.writeln();
      buf.writeln('STUDENT DETAILS:');
      for (final e in answers.entries) {
        if (e.value.trim().isEmpty) continue;
        buf.writeln('- ${e.key}: ${e.value}');
      }
    }
    if (features.isNotEmpty) {
      buf.writeln();
      buf.writeln('SELECTED FEATURES (must appear in the UI):');
      for (final f in features) {
        buf.writeln('- $f');
      }
    }
    buf
      ..writeln()
      ..writeln(
        'Include an AppBar with the app name and sections for each feature.',
      )
      ..writeln('Do not invent a different app name than the student details.');
    return buf.toString();
  }

  /// Legacy HTML brief for the chat builder path.
  String toHtmlCoderBrief() {
    final buf = StringBuffer()
      ..writeln('/no_think')
      ..writeln('Build one complete mobile-web app as a single HTML5 file.')
      ..writeln(
        'Output ONLY the HTML document. No markdown fences. No commentary.',
      )
      ..writeln('Start with <!DOCTYPE html>.')
      ..writeln(
        'NEVER output plain unstyled or non-functional HTML. Include modern CSS '
        'in <head><style> (:root variables, transitions, hover, bento cards) AND '
        'a complete <script> with vanilla JS so buttons/tabs/inputs/forms update '
        'state live. Offline only — no CDN. Close every tag.',
      )
      ..writeln(
        'Make it look like a premium phone app: max-width 420px, centered, '
        'rounded glass cards.',
      )
      ..writeln()
      ..writeln('APP TYPE: $appTypeName ($appTypeId)')
      ..writeln('COLOR THEME: $themeName — primary $themePrimary');


    if (answers.isNotEmpty) {
      buf.writeln();
      buf.writeln('STUDENT DETAILS:');
      for (final e in answers.entries) {
        buf.writeln('- ${e.key}: ${e.value}');
      }
    }
    if (features.isNotEmpty) {
      buf.writeln();
      buf.writeln('SELECTED FEATURES (must appear in the UI):');
      for (final f in features) {
        buf.writeln('- $f');
      }
    }
    return buf.toString();
  }
}

const kAppLabTypes = <AppLabType>[
  AppLabType(
    id: 'todo',
    name: 'Todo List',
    icon: Icons.check_box_outlined,
    featureOptions: [
      'Task list',
      'Add task',
      'Mark done',
      'Priority tags',
    ],
  ),
  AppLabType(
    id: 'expense',
    name: 'Expense Tracker',
    icon: Icons.account_balance_wallet_outlined,
    featureOptions: [
      'Expense list',
      'Add expense',
      'Category totals',
      'Savings goal',
    ],
  ),
  AppLabType(
    id: 'quiz',
    name: 'Quiz App',
    icon: Icons.quiz_outlined,
    featureOptions: [
      'Question screen',
      'Score tracker',
      'Multiple choice',
      'Restart quiz',
    ],
  ),
  AppLabType(
    id: 'calculator',
    name: 'Simple Calculator',
    icon: Icons.calculate_outlined,
    featureOptions: [
      'Number pad',
      'Add / subtract',
      'Multiply / divide',
      'Clear entry',
    ],
  ),
];

const kAppLabThemes = <AppLabTheme>[
  AppLabTheme(
    id: 'obsidian',
    name: 'Deep Obsidian Dark',
    primary: Color(0xFF6366F1),
    primaryHex: '#6366F1',
    background: Color(0xFF0B0F19),
    surface: Color(0xFF151B2B),
    onPrimary: Colors.white,
  ),
  AppLabTheme(
    id: 'silver',
    name: 'Clean Tech Silver',
    primary: Color(0xFF0EA5E9),
    primaryHex: '#0EA5E9',
    background: Color(0xFFF1F5F9),
    surface: Colors.white,
    onPrimary: Colors.white,
  ),
  AppLabTheme(
    id: 'neon',
    name: 'Neon Cyberpunk',
    primary: Color(0xFF22D3EE),
    primaryHex: '#22D3EE',
    background: Color(0xFF12061F),
    surface: Color(0xFF1E1033),
    onPrimary: Color(0xFF0B0F19),
  ),
];

AppLabType? appLabTypeById(String id) {
  for (final t in kAppLabTypes) {
    if (t.id == id) return t;
  }
  return null;
}

AppLabTheme? appLabThemeById(String id) {
  for (final t in kAppLabThemes) {
    if (t.id == id) return t;
  }
  return null;
}
