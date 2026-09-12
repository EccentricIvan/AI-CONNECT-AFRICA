import 'package:ai_connect_africa/features/app_dev_lab/app_build_coder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback dart and html include locked features', () {
    final intent = AppBuildIntent(
      appTypeId: 'todo',
      appTypeName: 'Todo List',
      themeId: 'obsidian',
      themeName: 'Deep Obsidian Dark',
      themePrimary: '#6366F1',
      answers: {'app_name': 'TaskTiny', 'purpose': 'School tasks'},
      features: ['Task list', 'Mark done'],
    );

    final dart = fallbackAppDart(intent);
    expect(dart, contains('class StudentApp'));
    expect(dart, contains('TaskTiny'));

    final html = fallbackAppHtml(intent);
    expect(html, contains('TaskTiny'));
    expect(html, contains('Task list'));
    expect(html, contains('<!DOCTYPE html>'));

    expect(intent.toCoderBrief(), contains('/no_think'));
  });

  test('extractDartSource accepts fenced flutter code', () {
    const raw = '''
```dart
import 'package:flutter/material.dart';
class StudentApp extends StatelessWidget {
  const StudentApp({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}
```
''';
    final dart = extractDartSource(raw);
    expect(dart, isNotNull);
    expect(dart!, contains('class StudentApp'));
    expect(dart, isNot(contains('```')));
  });
}
