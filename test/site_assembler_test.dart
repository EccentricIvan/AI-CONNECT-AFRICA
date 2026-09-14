import 'dart:io';

import 'package:ai_connect_africa/features/website/site_assembler.dart';
import 'package:ai_connect_africa/features/website/site_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every vertical assembles a complete page with no stray tokens', () async {
    final a = SiteAssembler();
    for (final v in kVerticals) {
      final html = await a.assemble(
        vertical: v,
        selected: v.defaultBlocks,
        answers: {'site_name': '${v.name} Demo'},
      );
      expect(html, contains('<!DOCTYPE html>'), reason: v.id);
      expect(html.contains('{{'), isFalse, reason: '${v.id} left a raw token');
      expect(html, contains(v.brand), reason: '${v.id} lost its palette');
      expect(html, contains('id="contact"'), reason: '${v.id} missing core block');
    }
  });

  test('sections always follow canonical order regardless of selection order', () async {
    final html = await SiteAssembler().assemble(
      vertical: kVerticals.first,
      selected: {'faq', 'stats', 'pricing', 'features'},
    );
    // The hero block anchors itself as "top" so the nav brand can link to it.
    final positions = ['top', 'features', 'pricing', 'faq', 'contact']
        .map((id) => html.indexOf('id="$id"'))
        .toList();
    for (final p in positions) {
      expect(p, greaterThan(-1));
    }
    final sorted = [...positions]..sort();
    expect(positions, sorted, reason: 'blocks emitted out of canonical order');
  });

  test('unselected optional blocks are absent and not linked in the nav', () async {
    final html = await SiteAssembler().assemble(
      vertical: kVerticals.first,
      selected: const {},
    );
    expect(html.contains('id="pricing"'), isFalse);
    expect(html.contains('href="#pricing"'), isFalse);
    expect(html, contains('id="about"'));
  });

  test('student input is escaped so a name cannot inject markup', () async {
    final html = await SiteAssembler().assemble(
      vertical: kVerticals.first,
      selected: const {},
      answers: {'site_name': '<script>alert(1)</script>'},
    );
    expect(html.contains('<script>alert(1)</script>'), isFalse);
    expect(html, contains('&lt;script&gt;'));
  });

  test('model copy is used but never replaces a student answer', () async {
    final html = await SiteAssembler().assemble(
      vertical: kVerticals.first,
      selected: const {},
      answers: {'site_name': 'Real Name'},
      modelCopy: {'site_name': 'Model Name', 'about_title': 'Model Heading'},
    );
    expect(html, contains('Real Name'));
    expect(html.contains('Model Name'), isFalse);
    expect(html, contains('Model Heading'));
  });

  test('empty model output falls back to premium defaults', () async {
    final html = await SiteAssembler().assemble(
      vertical: kVerticals.first,
      selected: {'features'},
      modelCopy: {'feature1_title': '   ', 'feature1_text': ''},
    );
    expect(html, contains(kVerticals.first.copy['feature1_title']!));
    expect(html.contains('{{'), isFalse);
  });

  test('renders a sample page for visual inspection', () async {
    final v = verticalById('techstartup')!;
    final html = await SiteAssembler().assemble(
      vertical: v,
      selected: {...v.defaultBlocks, 'pricing', 'testimonials', 'faq', 'cta'},
      answers: {'site_name': 'Kigali Cloud'},
    );
    final out = File('${Directory.systemTemp.path}/site_preview.html');
    await out.writeAsString(html);
    // ignore: avoid_print
    print('PREVIEW ${out.path} (${html.length} bytes)');
    expect(html.length, greaterThan(8000));
  });
}
