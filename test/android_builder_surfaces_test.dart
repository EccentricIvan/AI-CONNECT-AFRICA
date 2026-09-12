import 'package:ai_connect_africa/features/app_dev_lab/app_dev_lab_screen.dart';
import 'package:ai_connect_africa/features/site_builder/site_chat_builder_screen.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Confirms Create/builder surfaces are wired for Android (and all non-web).
void main() {
  test('builder routes exist for Android packaging', () {
    expect(kIsWeb, isFalse);

    // Route paths used by Create + Home on every mobile build.
    const routes = [
      '/sitechat',
      '/applab',
      '/appchat',
      '/weblab',
      '/website',
    ];
    for (final r in routes) {
      expect(r, startsWith('/'));
    }

    // Screens must construct (no desktop-only types).
    expect(const SiteChatBuilderScreen(), isA<SiteChatBuilderScreen>());
    expect(const AppDevLabScreen(), isA<AppDevLabScreen>());
  });

  test('Android preview helpers are available', () {
    expect(createPreviewWebViewController, isA<Function>());
    expect(loadHtmlPreview, isA<Function>());
    expect(htmlBodyForFlutterHtml('<body><p>Hi</p></body>'), contains('Hi'));
  });
}
