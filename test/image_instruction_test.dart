import 'dart:io';
import 'dart:typed_data';

import 'package:ai_connect_africa/shared/coding/html_images.dart';
import 'package:ai_connect_africa/shared/coding/image_instruction.dart';
import 'package:ai_connect_africa/shared/coding/image_palette.dart';
import 'package:ai_connect_africa/shared/coding/interactive_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _page = '''
<!DOCTYPE html><html><head><title>Sweet Treats</title><style>.hero{padding:40px}</style></head>
<body>
<header><nav><a href="#">Home</a></nav></header>
<section class="hero"><h1>Sweet Treats</h1></section>
<section id="about"><h2>About Us</h2><p>We bake every morning.</p></section>
<section class="menu"><h2>Our Menu</h2><img src="bread.jpg" alt="bread"><img src="cake.jpg" alt="cake"></section>
<footer>© 2026</footer>
</body></html>
''';

PickedImage _pic([String name = 'shop_front.png']) => PickedImage(
  name: name,
  bytes: Uint8List.fromList([1, 2, 3, 4]),
  mime: 'image/png',
);

String _uri(PickedImage p) => p.dataUri;

void main() {
  final pic = _pic();

  test('"make this the logo" puts it in the top bar', () {
    final r = applyImageInstruction(_page, 'make this the logo', [pic]);
    final header = r.html.substring(
      r.html.indexOf('<header'),
      r.html.indexOf('</header>'),
    );
    expect(header, contains(_uri(pic)));
    expect(r.html, isNot(contains('otic-gallery')));
  });

  test('logo on a page with no top bar goes first on the page', () {
    const bare = '<html><head></head><body><h1>Hi</h1></body></html>';
    final r = applyImageInstruction(bare, 'use this as my logo', [pic]);
    expect(r.html.indexOf(_uri(pic)), lessThan(r.html.indexOf('<h1>')));
  });

  test('"use it as the background" fills the banner, with a readable wash', () {
    final r = applyImageInstruction(_page, 'use it as the background', [pic]);
    final hero = RegExp(
      r'<section class="hero"[^>]*>',
    ).firstMatch(r.html)!.group(0)!;
    expect(hero, contains(_uri(pic)));
    expect(hero, contains('rgba(0,0,0,.45)'));
    expect(r.summary, contains('banner background'));
  });

  test('"background of the whole page" goes on <body>', () {
    final r = applyImageInstruction(
      _page,
      'make it the background of the whole page',
      [pic],
    );
    final body = RegExp(r'<body[^>]*>').firstMatch(r.html)!.group(0)!;
    expect(body, contains(_uri(pic)));
  });

  test('"put this in the about section" lands under the About heading', () {
    final r = applyImageInstruction(_page, 'put this in the about section', [
      pic,
    ]);
    final about = r.html.indexOf('About Us');
    final at = r.html.indexOf(_uri(pic));
    expect(at, greaterThan(about));
    expect(at, lessThan(r.html.indexOf('We bake every morning')));
  });

  test('"above the menu" lands before the Menu heading', () {
    final r = applyImageInstruction(_page, 'add this picture above the menu', [
      pic,
    ]);
    expect(r.html.indexOf(_uri(pic)), lessThan(r.html.indexOf('Our Menu')));
    expect(
      r.html.indexOf(_uri(pic)),
      greaterThan(r.html.indexOf('We bake every morning')),
    );
  });

  test('"replace the second picture" swaps exactly that one', () {
    final r = applyImageInstruction(
      _page,
      'replace the second picture with this',
      [pic],
    );
    final imgs = listPageImages(r.html);
    expect(imgs[0].src, 'bread.jpg');
    expect(imgs[1].src, _uri(pic));
    expect(r.html, contains('otic-img-1'));
  });

  test('styling words style the placed picture, without the model', () {
    final r = applyImageInstruction(
      _page,
      'put it at the top and make it round with a shadow',
      [pic],
    );
    expect(r.html, contains('.otic-img-1{border-radius:50%'));
    expect(r.html, contains('box-shadow'));
    expect(r.modelInstruction, isNull);
  });

  test(
    'styling this cannot do is handed to the model, aimed at the picture',
    () {
      final r = applyImageInstruction(
        _page,
        'put it in the about section and tilt it slightly',
        [pic],
      );
      expect(r.modelInstruction, contains('.otic-img-1'));
      expect(r.modelInstruction, contains('tilt it slightly'));
    },
  );

  test(
    '"use the colours of this picture" restyles only — no picture placed',
    () {
      final r = applyImageInstruction(
        _page,
        'use the colours of this picture',
        [pic],
      );
      expect(r.wantsColours, isTrue);
      expect(r.html, _page);
    },
  );

  test('a named colour is not a request for the picture\'s colours', () {
    final r = applyImageInstruction(_page, 'add this and make the theme blue', [
      pic,
    ]);
    expect(r.wantsColours, isFalse);
  });

  test('no clear place: the gallery, so the picture is always visible', () {
    final r = applyImageInstruction(_page, '', [pic]);
    expect(r.html, contains('otic-gallery'));
    expect(r.html.indexOf('otic-gallery'), lessThan(r.html.indexOf('<footer')));
  });

  test('extra pictures beyond a single spot go to the gallery', () {
    final r = applyImageInstruction(_page, 'make this the logo', [
      pic,
      _pic('b.png'),
      _pic('c.png'),
    ]);
    expect(r.html, contains('otic-gallery'));
    expect(r.summary, contains('2 pictures to the gallery'));
  });

  test(
    'every real template takes every kind of instruction and stays renderable',
    () {
      final templates = [
        ...Directory('assets/templates').listSync().whereType<File>(),
        ...Directory('assets/templates/apps').listSync().whereType<File>(),
      ].where((f) => f.path.endsWith('.html'));
      const instructions = [
        'make this the logo',
        'use it as the background',
        'put this in the about section',
        'replace the first picture',
        'put it at the bottom and make it smaller',
        'use the colours of this photo',
        '',
      ];
      for (final f in templates) {
        final html = f.readAsStringSync();
        for (final instruction in instructions) {
          final r = applyImageInstruction(html, instruction, [pic]);
          final reason = '${f.path} :: "$instruction"';
          if (!r.wantsColours) {
            expect(r.html, contains(_uri(pic)), reason: reason);
          }
          expect(
            RegExp('<body', caseSensitive: false).allMatches(r.html).length,
            1,
            reason: reason,
          );
          expect(hasVisibleContent(r.html), isTrue, reason: reason);
        }
      }
    },
  );

  group('paletteStyleFromImageBytes', () {
    Uint8List png(void Function(img.Image) paint) {
      final image = img.Image(width: 40, height: 40);
      paint(image);
      return Uint8List.fromList(img.encodePng(image));
    }

    test('a mostly red photo gives a red accent and a pale background', () {
      final bytes = png((i) {
        img.fill(i, color: img.ColorRgb8(255, 255, 255));
        img.fillRect(
          i,
          x1: 0,
          y1: 0,
          x2: 39,
          y2: 29,
          color: img.ColorRgb8(200, 30, 40),
        );
      });
      final style = paletteStyleFromImageBytes(bytes)!;
      final accent = int.parse(style.accentColor!.substring(1), radix: 16);
      expect(
        (accent >> 16) & 0xff,
        greaterThan(150),
        reason: style.accentColor,
      );
      expect(accent & 0xff, lessThan(90), reason: style.accentColor);
      final bg = int.parse(style.backgroundColor!.substring(1), radix: 16);
      expect(bg & 0xff, greaterThan(220), reason: style.backgroundColor);
    });

    test('a black and white picture still gives a usable palette', () {
      final bytes = png((i) {
        img.fill(i, color: img.ColorRgb8(255, 255, 255));
        img.fillRect(
          i,
          x1: 0,
          y1: 0,
          x2: 19,
          y2: 39,
          color: img.ColorRgb8(90, 90, 90),
        );
      });
      expect(paletteStyleFromImageBytes(bytes)?.accentColor, isNotNull);
    });

    test('bytes that are not a picture give null', () {
      expect(paletteStyleFromImageBytes(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
