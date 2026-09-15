import 'package:ai_connect_africa/features/app_dev_lab/app_dev_lab_screen.dart';
import 'package:ai_connect_africa/features/web_dev_lab/web_dev_lab_screen.dart';
import 'package:ai_connect_africa/shared/coding/code_lab.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/preview_contract.dart';

/// Both labs now run on the same [CodeLabScaffold]: lessons on the left, the
/// page that code produces on the right, with no coding model in between.
///
/// These assertions are the lab equivalent of the site-builder fidelity check
/// — every lesson a student can open must reach the browser engine unchanged
/// and must render offline on both Android and Windows.
void main() {
  final labs = <String, List<CodeLabLesson>>{
    'App Dev Lab': appLabLessons,
    'Web Dev Lab': webLabLessons,
  };

  /// A *resource* the page must fetch to render: an image, stylesheet, script
  /// or font. An `<a href>` is deliberately not included — teaching links is
  /// fine, and a link that cannot navigate offline still renders correctly,
  /// whereas an image that never loads looks to the student like their own
  /// mistake.
  final networkRef = RegExp(
    r'''src\s*=\s*['"]?\s*(https?:)?//|<link[^>]+href\s*=\s*['"]?\s*(https?:)?//|@import\s+url\(\s*['"]?\s*(https?:)?//|cdn\.|fonts\.googleapis''',
    caseSensitive: false,
  );

  group('every lesson is a complete offline document', () {
    labs.forEach((lab, lessons) {
      test('$lab has lessons, each a full HTML document', () {
        expect(lessons, isNotEmpty);
        for (final l in lessons) {
          expect(
            l.starterCode,
            contains(RegExp('<!DOCTYPE html>', caseSensitive: false)),
            reason: '${l.title} is not a complete document',
          );
          expect(l.starterCode.toLowerCase(), contains('</html>'));
          expect(l.title, isNotEmpty);
          expect(l.instruction, isNotEmpty);
        }
      });

      test('$lab declares a charset in every lesson', () {
        for (final l in lessons) {
          // Without this the preview's file:// load falls back to the OS
          // codepage and any non-ASCII character renders as mojibake.
          expect(
            l.starterCode.toLowerCase(),
            contains('charset'),
            reason: '${l.title} would render mojibake on Windows',
          );
        }
      });

      test('$lab never reaches for the network', () {
        for (final l in lessons) {
          final hit = networkRef.firstMatch(l.starterCode);
          expect(
            hit,
            isNull,
            reason: '${l.title} needs the internet: "${hit?.group(0)}"',
          );
        }
      });

      test('$lab lessons reach the preview byte-identical', () {
        for (final l in lessons) {
          expect(
            prepareHtmlForPreview(l.starterCode),
            l.starterCode,
            reason: '${l.title} is altered on the way to the preview',
          );
          for (final invented in kInventedPreviewContent) {
            expect(l.starterCode, isNot(contains(invented)));
          }
        }
      });
    });

    test('App Dev Lab avoids localStorage', () {
      // Android loads preview HTML on an about:blank origin, where storage
      // throws — a lesson built on it would fail on Android but pass on
      // Windows, which is worse than not teaching it here at all.
      for (final l in appLabLessons) {
        expect(
          l.starterCode,
          isNot(contains('localStorage')),
          reason: '${l.title} would break on Android',
        );
      }
    });
  });
}
