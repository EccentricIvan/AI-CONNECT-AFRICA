import 'dart:io';
import 'dart:typed_data';

import 'package:ai_connect_africa/shared/coding/interactive_html.dart';
import 'package:ai_connect_africa/shared/coding/ui_look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A screenshot: [bg] page, a [bar] across the top, and a grid of cards.
Uint8List _screenshot({
  required int width,
  required int height,
  required img.Color bg,
  required img.Color bar,
  required img.Color card,
  required int columns,
  required int rows,
  required num radius,
}) {
  final shot = img.Image(width: width, height: height);
  img.fill(shot, color: bg);
  final barH = (height * 0.08).round();
  img.fillRect(shot, x1: 0, y1: 0, x2: width - 1, y2: barH, color: bar);
  final gap = (width * 0.04).round();
  final cardW = ((width - gap * (columns + 1)) / columns).floor();
  final cardH = ((height - barH - gap * (rows + 1)) / rows).floor();
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      final x = gap + c * (cardW + gap);
      final y = barH + gap + r * (cardH + gap);
      img.fillRect(
        shot,
        x1: x,
        y1: y,
        x2: x + cardW,
        y2: y + cardH,
        color: card,
        radius: radius,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(shot));
}

int _channel(String hex, int shift) =>
    (int.parse(hex.substring(1), radix: 16) >> shift) & 0xff;

void main() {
  group('isLookRequest', () {
    test('recognises "make it like this" requests', () {
      for (final s in [
        'make the UI like this',
        'make my app look like this',
        'same style as this picture',
        'copy this design',
        'match the design',
        'I want this style',
      ]) {
        expect(isLookRequest(s), isTrue, reason: s);
      }
    });

    test('leaves placement and colour requests alone', () {
      for (final s in [
        'make this the logo',
        'put this in the about section',
        'use the colours of this picture',
        'replace the second picture',
        '',
      ]) {
        expect(isLookRequest(s), isFalse, reason: s);
      }
    });
  });

  group('analyzeUiScreenshot', () {
    test('a dark phone dashboard with rounded cards in two columns', () {
      final look = analyzeUiScreenshot(
        _screenshot(
          width: 400,
          height: 800,
          bg: img.ColorRgb8(17, 24, 39),
          bar: img.ColorRgb8(124, 58, 237),
          card: img.ColorRgb8(45, 55, 72),
          columns: 2,
          rows: 3,
          radius: 20,
        ),
      )!;
      expect(look.dark, isTrue);
      expect(look.cards, isTrue);
      expect(look.columns, 2);
      expect(look.radius, greaterThanOrEqualTo(12), reason: '${look.radius}');
      expect(
        _channel(look.bar, 16),
        greaterThan(90),
        reason: look.bar,
      ); // purple
      expect(_channel(look.bar, 0), greaterThan(180), reason: look.bar);
    });

    test('a light desktop page with square cards in three columns', () {
      final look = analyzeUiScreenshot(
        _screenshot(
          width: 1280,
          height: 800,
          bg: img.ColorRgb8(255, 255, 255),
          bar: img.ColorRgb8(37, 99, 235),
          card: img.ColorRgb8(226, 232, 240),
          columns: 3,
          rows: 2,
          radius: 0,
        ),
      )!;
      expect(look.dark, isFalse);
      expect(look.cards, isTrue);
      expect(look.columns, 3);
      expect(look.radius, lessThanOrEqualTo(6), reason: '${look.radius}');
      expect(look.accent, isNotNull);
      expect(
        _channel(look.accent!, 0),
        greaterThan(180),
        reason: look.accent,
      ); // blue
    });

    test('bytes that are not a picture give null', () {
      expect(analyzeUiScreenshot(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  test(
    'applyUiLook restyles every real template and a second look replaces the first',
    () {
      const dark = UiLook(
        dark: true,
        background: '#111827',
        bar: '#7c3aed',
        surface: '#2d3748',
        cards: true,
        radius: 18,
        columns: 2,
        accent: '#7c3aed',
      );
      const light = UiLook(
        dark: false,
        background: '#ffffff',
        bar: '#2563eb',
        surface: '#e2e8f0',
        cards: true,
        radius: 0,
        columns: 3,
        accent: '#2563eb',
      );
      final templates = [
        ...Directory('assets/templates').listSync().whereType<File>(),
        ...Directory('assets/templates/apps').listSync().whereType<File>(),
      ].where((f) => f.path.endsWith('.html'));
      for (final f in templates) {
        final once = applyUiLook(f.readAsStringSync(), dark);
        final twice = applyUiLook(once, light);
        expect(
          RegExp('id="otic-look"').allMatches(twice).length,
          1,
          reason: f.path,
        );
        expect(
          RegExp('id="otic-style"').allMatches(twice).length,
          1,
          reason: f.path,
        );
        expect(twice, contains('repeat(3,'), reason: f.path);
        expect(
          twice,
          isNot(contains('repeat(2,minmax(0,1fr)) !important;gap:16px')),
          reason: f.path,
        );
        expect(hasVisibleContent(twice), isTrue, reason: f.path);
      }
    },
  );

  test('the dark look makes text light and cards rounded', () {
    const look = UiLook(
      dark: true,
      background: '#111827',
      bar: '#7c3aed',
      surface: '#2d3748',
      cards: true,
      radius: 24,
      columns: 0,
    );
    final out = applyUiLook(
      '<html><head></head><body><div class="card">x</div></body></html>',
      look,
    );
    expect(out, contains('color:#e5e7eb'));
    expect(out, contains('border-radius:24px'));
    expect(out, contains('border-radius:999px')); // very round → pill buttons
    expect(out, isNot(contains('grid-template-columns')));
  });
}
