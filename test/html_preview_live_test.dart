import 'dart:io';

import 'package:ai_connect_africa/features/app_dev_lab/app_dev_lab_screen.dart';
import 'package:ai_connect_africa/features/site_builder/site_chat_builder_screen.dart';
import 'package:ai_connect_africa/shared/widgets/html_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const salonFills = {
    'salon_name': 'Glow Beauty Salon',
    'tagline': 'Look your best every day',
    'description': 'Premium hair, nails, and makeup in Kampala.',
    'phone': '0789789765',
    'address': 'Acacia Mall',
    'about': 'Expert stylists in a calm studio.',
    'price_hair': 'UGX 25,000',
    'price_nails': 'UGX 20,000',
    'price_facial': 'UGX 35,000',
    'price_makeup': 'UGX 40,000',
    'hours_weekday': '9am – 6pm',
    'hours_saturday': '9am – 5pm',
    'hours_sunday': 'Closed',
  };

  Future<String> filledSalonHtml() async {
    var html = await File('assets/templates/salon.html').readAsString();
    for (final e in salonFills.entries) {
      html = html.replaceAll('{{${e.key}}}', e.value);
    }
    return html;
  }

  test('salon website fills cleanly as a complete HTML document', () async {
    final html = await filledSalonHtml();
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('Glow Beauty Salon'));
    expect(html, contains('0789789765'));
    expect(html, contains('Acacia Mall'));
    expect(html, isNot(contains('{{salon_name}}')));
  });

  test('htmlBodyForFlutterHtml extracts body for in-app fallback', () async {
    final html = await filledSalonHtml();
    final body = htmlBodyForFlutterHtml(html);
    expect(body, contains('Glow Beauty Salon'));
    expect(body, contains('Acacia Mall'));
  });

  test('file:// preview target is written for Simple Browser load', () async {
    final html = await filledSalonHtml();
    final dir = await Directory.systemTemp.createTemp('otic_preview_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final previewFile = File(p.join(dir.path, 'otic_live_preview.html'));
    await previewFile.writeAsString(html, flush: true);
    expect(await previewFile.exists(), isTrue);
    expect(await previewFile.length(), greaterThan(1000));
    expect(Uri.file(previewFile.path).isScheme('file'), isTrue);
  });

  test('builder screens exist for Android packaging', () {
    expect(kIsWeb, isFalse);
    expect(const SiteChatBuilderScreen(), isA<SiteChatBuilderScreen>());
    expect(const AppDevLabScreen(), isA<AppDevLabScreen>());
    expect(createPreviewWebViewController, isA<Function>());
    expect(loadHtmlPreview, isA<Function>());
  });

  test('plain-text fallback extracts salon name for Android WebView failure',
      () async {
    final html = await filledSalonHtml();
    final plain = htmlPlainText(html);
    expect(plain, contains('Glow Beauty Salon'));
    expect(plain, contains('Acacia Mall'));
  });
}
