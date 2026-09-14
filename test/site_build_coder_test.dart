import 'package:ai_connect_africa/features/site_builder/site_build_coder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('intent brief records every selected feature for the coder', () {
    final intent = SiteBuildIntent(
      templateId: 'bakery',
      templateName: 'Bakery / Restaurant',
      themeName: 'Ocean Blue',
      themePrimary: '#2563eb',
      answers: {
        'business_name': 'Sweet Treats',
        'phone': '+256 700 123 456',
      },
      content: {
        'tagline': 'Fresh baked daily',
        'description': 'Local ingredients every morning.',
      },
    );

    final brief = intent.toCoderBrief();
    expect(brief, contains('Bakery / Restaurant'));
    expect(brief, contains('Ocean Blue'));
    expect(brief, contains('Sweet Treats'));
    expect(brief, contains('Fresh baked daily'));
    expect(brief, contains('Output ONLY the HTML'));
  });

  test('extractHtmlDocument accepts fenced and raw HTML', () {
    const fenced = '''
Here you go:
```html
<!DOCTYPE html>
<html><body><h1>Hi</h1></body></html>
```
''';
    expect(extractHtmlDocument(fenced), contains('<!DOCTYPE html>'));
    expect(extractHtmlDocument(fenced), contains('<h1>Hi</h1>'));

    const raw = '<!DOCTYPE html><html><body>Ok</body></html>';
    expect(extractHtmlDocument(raw), contains('Ok'));
  });

  test('extractHtmlDocument salvages non-HTML chatter into interactive shell', () {
    final out = extractHtmlDocument('Just an explanation with no markup.');
    expect(out, isNotNull);
    expect(out, contains('<!DOCTYPE html>'));
    expect(out!.toLowerCase(), contains('otic_interactive_runtime'));
  });
}
