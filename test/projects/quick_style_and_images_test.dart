import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/features/projects/scaffold/project_scaffold.dart';
import 'package:ai_connect_africa/shared/coding/html_images.dart';
import 'package:ai_connect_africa/shared/coding/quick_style_edit.dart';

const _page = '<html><head><title>T</title></head><body>'
    '<header><a href="#">Brand</a></header>'
    '<img src="hero.jpg" alt="Hero" class="hero-img">'
    '<footer>Footer</footer></body></html>';

final _png = PickedImage(
  name: 'my_shop-front.png',
  bytes: Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]),
  mime: 'image/png',
);

void main() {
  group('parseQuickStyleRequest', () {
    test('understands what students type', () {
      expect(parseQuickStyleRequest('make the text red')!.textColor, '#dc2626');
      expect(parseQuickStyleRequest('I want this colour of text: #123abc')!.textColor, '#123abc');
      expect(parseQuickStyleRequest('change the background to light blue')!.backgroundColor,
          '#93c5fd');
      expect(parseQuickStyleRequest('headings dark green')!.headingColor, '#166534');
      expect(parseQuickStyleRequest('buttons purple')!.accentColor, '#7c3aed');
      expect(parseQuickStyleRequest('make it orange')!.accentColor, '#ea580c');
      expect(parseQuickStyleRequest('use a handwriting font')!.fontFamily, 'handwriting');
      expect(parseQuickStyleRequest('make the text bigger')!.fontScale, 1.15);
      expect(
        parseQuickStyleRequest('make the text bigger',
                current: const QuickStyle(fontScale: 1.15))!
            .fontScale,
        1.3,
      );
    });

    test('leaves layout requests to the coder model', () {
      expect(parseQuickStyleRequest('add a pricing section with three plans'), isNull);
      expect(parseQuickStyleRequest('center the text'), isNull);
      expect(parseQuickStyleRequest('make the logo red'), isNull);
      expect(parseQuickStyleRequest('I want the second card to have a blue border'), isNull);
      expect(parseQuickStyleRequest('change it so that the page feels more green and calm'), isNull);
    });

    test('bars get their own colour, not the buttons', () {
      final s = parseQuickStyleRequest('I want a white navbar with my logo')!;
      expect(s.barColor, '#ffffff');
      expect(s.accentColor, isNull);
      final html = applyQuickStyle(_page, s);
      expect(html, contains('header,nav'));
      expect(html, contains('color:#111827'));
    });

    test('button text stays readable on light colours', () {
      expect(readableTextOn('#ffffff'), '#111827');
      expect(readableTextOn('#eab308'), '#111827');
      expect(readableTextOn('#1e3a8a'), '#ffffff');
      final html = applyQuickStyle(_page, const QuickStyle(accentColor: '#fef3c7'));
      expect(html, contains('color:#111827 !important}'));
    });
  });

  group('applyQuickStyle', () {
    test('writes one block before </head> and round-trips', () {
      var html = applyQuickStyle(_page, const QuickStyle(textColor: '#dc2626'));
      html = applyQuickStyle(html, readQuickStyle(html).merge(const QuickStyle(fontScale: 1.3)));
      expect('<style id="otic-style">'.allMatches(html).length, 1);
      expect(html.indexOf('otic-style'), lessThan(html.indexOf('</head>')));
      final back = readQuickStyle(html);
      expect(back.textColor, '#dc2626');
      expect(back.fontScale, 1.3);
      expect(html, contains('font-size:130%'));
    });

    test('an empty style removes the block', () {
      final styled = applyQuickStyle(_page, const QuickStyle(accentColor: '#2563eb'));
      expect(applyQuickStyle(styled, const QuickStyle()), _page);
    });

    test('rejects colours that could break out of CSS', () {
      expect(normalizeCssColor('red;}</style><script>'), isNull);
      expect(QuickStyle.fromJson({'text': 'x;}'}).textColor, isNull);
    });
  });

  group('pictures', () {
    test('lists, replaces and keeps the layout classes', () {
      expect(listPageImages(_page).single.label, 'Hero');
      final html = replacePageImage(_page, 0, _png);
      expect(html, contains('class="hero-img"'));
      expect(html, contains('src="data:image/png;base64,'));
      expect(html, contains('alt="my shop front"'));
    });

    test('gallery goes before the footer and grows on a second add', () {
      var html = addToGallery(_page, [_png]);
      expect(html.indexOf('otic-gallery'), lessThan(html.indexOf('<footer')));
      html = addToGallery(html, [_png, _png]);
      expect('<figure>'.allMatches(html).length, 3);
      expect('<section class="otic-gallery"'.allMatches(html).length, 1);
    });

    test('logo lands in the header', () {
      final html = setLogo(_page, _png);
      final header = html.substring(html.indexOf('<header'), html.indexOf('</header>'));
      expect(header, contains('data:image/png'));
    });

    test('the coder model sees placeholders, not base64, and they come back', () {
      final page = replacePageImage(_page, 0, _png);
      final masked = maskEmbeddedImages(page);
      expect(masked.text, isNot(contains('base64')));
      expect(masked.text, contains('images/otic-embedded-1.png'));
      final edited = masked.text.replaceFirst('<footer>', '<footer class="dark">');
      final restored = masked.restore(edited);
      expect(restored, contains('data:image/png;base64,'));
      expect(restored, contains('<footer class="dark">'));
    });

    test('saved projects get real image files instead of data URIs', () {
      final images = <String, Uint8List>{};
      final page = addToGallery(replacePageImage(_page, 0, _png), [_png]);
      final files = buildWebsiteProject(title: 'Shop', html: page, images: images);
      expect(files['frontend/index.html'], isNot(contains('data:image/png')));
      expect(files['frontend/index.html'], contains('src="images/picture-1.png"'));
      // The same picture used twice is stored once.
      expect(images.keys, ['frontend/images/picture-1.png']);
      expect(images.values.single, _png.bytes);
    });
  });
}
