import 'dart:typed_data';

import 'package:ai_connect_africa/features/app_dev_lab/app_build_intent.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_type_catalog.dart';
import 'package:ai_connect_africa/features/app_dev_lab/app_type_classifier.dart';
import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:ai_connect_africa/features/site_builder/site_template_catalog.dart';
import 'package:ai_connect_africa/features/site_builder/site_template_classifier.dart';
import 'package:ai_connect_africa/shared/coding/html_images.dart';
import 'package:ai_connect_africa/shared/coding/interactive_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyAppType', () {
    test('picks the type the description is about', () {
      expect(
        classifyAppType('a chicken farm app to log egg harvests').id,
        'farm',
      );
      expect(classifyAppType('help my class track homework tasks').id, 'todo');
    });

    test('the most specific match wins, whatever the catalog order', () {
      // "shop" alone would pick the online shop; "till" + "cashier" outscore it.
      expect(
        classifyAppType('a shop till for the cashier at my shop').id,
        'pos',
      );
      expect(classifyAppType('a to-do app for my shop').id, 'todo');
    });

    test('short keywords only match whole words', () {
      // "purpose" contains "pos"; it must not make this a sales till.
      expect(
        classifyAppType('an app whose purpose is to share poems').id,
        isNot('pos'),
      );
    });

    test('an unmatched description still resolves to a type', () {
      final type = classifyAppType(
        'something to help grandma remember birthdays',
      );
      expect(type, same(kGenericAppType));
      expect(type.templateId, 'generic');
    });

    test('every catalog type is reachable from its own keywords', () {
      for (final type in kAppTypes) {
        expect(type.keywords, isNotEmpty, reason: type.id);
        expect(
          classifyAppType(type.keywords.first).id,
          type.id,
          reason: type.id,
        );
      }
    });
  });

  group('classifySiteTemplate', () {
    test('picks the site type the description is about', () {
      expect(
        classifySiteTemplate('a website for our church choir').id,
        'church',
      );
      expect(
        classifySiteTemplate('a school dashboard showing exam results').id,
        'edudash',
      );
      expect(
        classifySiteTemplate('landing page for my AI chatbot').id,
        'saasai',
      );
    });

    test('short keywords only match whole words', () {
      // "space" contains "spa"; "said" contains "ai".
      final t = classifySiteTemplate('a space where my friends said hello');
      expect(t.id, isNot('salon'));
      expect(t.id, isNot('saasai'));
    });

    test('an unmatched description falls back to a real template', () {
      final t = classifySiteTemplate('a page for my football club fixtures');
      expect(t.id, kGenericSiteTemplate.id);
      expect(kSiteTemplates.map((e) => e.id), contains(t.id));
    });
  });

  group('briefs carry the description', () {
    AppBuildIntent appIntent({String description = ''}) => AppBuildIntent(
      appTypeId: 'custom',
      appTypeName: 'Custom App',
      themeId: '1',
      themeName: 'Ocean Blue',
      themePrimary: '#2563eb',
      answers: const {},
      features: const [],
      description: description,
    );

    test('app brief puts the description first as the spec', () {
      final brief = appIntent(
        description: 'track school fees for S2',
      ).toHtmlCoderBrief();
      expect(brief, contains('DESCRIPTION'));
      expect(brief, contains('track school fees for S2'));
    });

    test('app brief without a description is unchanged', () {
      expect(appIntent().toHtmlCoderBrief(), isNot(contains('DESCRIPTION')));
    });

    test('site brief carries the description', () {
      final brief = SiteBuildIntent(
        templateId: 'techstartup',
        templateName: 'Tech Startup',
        themeName: 'Default',
        themePrimary: null,
        answers: const {},
        content: const {},
        description: 'football club with fixtures and players',
      ).toCoderBrief();
      expect(brief, contains('football club with fixtures and players'));
    });
  });

  group('extractPageTitle', () {
    test('prefers <title>, then the first <h1>', () {
      expect(
        extractPageTitle('<title> Fee Tracker </title><h1>Other</h1>'),
        'Fee Tracker',
      );
      expect(
        extractPageTitle('<body><h1>Egg <b>Log</b></h1></body>'),
        'Egg Log',
      );
    });

    test('null when the page has neither', () {
      expect(extractPageTitle('<body><p>hi</p></body>'), isNull);
      expect(extractPageTitle('<title>  </title>'), isNull);
    });
  });

  group('hasVisibleContent', () {
    test('a real page passes', () {
      expect(
        hasVisibleContent(
          '<html><head><style>body{color:red}</style></head><body>'
          '<h1>Fee Tracker</h1><p>Record who has paid school fees this term.</p>'
          '</body></html>',
        ),
        isTrue,
      );
    });

    test('a reply that ran out of tokens inside <style> fails', () {
      // What a truncated coder reply repairs into: all CSS, empty body.
      final css = List.filled(
        80,
        '.card{padding:12px;border-radius:14px}',
      ).join('\n');
      expect(
        hasVisibleContent(
          '<!DOCTYPE html><html><head><style>$css</style></head><body></body></html>',
        ),
        isFalse,
      );
      expect(
        hasVisibleContent('<!DOCTYPE html><html><head><style>$css'),
        isFalse,
      );
    });

    test('script text does not count as content', () {
      final js = List.filled(20, 'document.body.append("x");').join();
      expect(hasVisibleContent('<body><script>$js</script></body>'), isFalse);
    });
  });

  group('applyPickedImages', () {
    const page = '<html><body><main>x</main><footer>f</footer></body></html>';
    final image = PickedImage(
      name: 'shop_front.png',
      bytes: Uint8List.fromList([1, 2, 3]),
      mime: 'image/png',
    );

    test('adds attached pictures to a gallery before the footer', () {
      final out = applyPickedImages(page, [image]);
      expect(out, contains('data:image/png;base64,'));
      expect(out.indexOf('otic-gallery'), lessThan(out.indexOf('<footer')));
    });

    test('leaves the page alone when nothing was attached', () {
      expect(applyPickedImages(page, const []), page);
    });
  });
}
