import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_connect_africa/services/ocr/ocr_engine.dart';
import 'package:ai_connect_africa/services/offline_storage_service.dart';
import 'package:ai_connect_africa/services/pdf/diagram_detector.dart';

/// A white page with black rectangles drawn on it.
RenderedPage page(int w, int h, List<(int, int, int, int)> blackRects) {
  final px = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  for (final (l, t, r, b) in blackRects) {
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        final i = (y * w + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = 0;
      }
    }
  }
  return RenderedPage(bgra: px, width: w, height: h);
}

/// Outline of a box with a cross through it — line art, like a diagram.
List<(int, int, int, int)> drawing(int l, int t, int r, int b) => [
  (l, t, r, t + 3),
  (l, b - 3, r, b),
  (l, t, l + 3, b),
  (r - 3, t, r, b),
  (l, (t + b) ~/ 2, r, (t + b) ~/ 2 + 3),
  ((l + r) ~/ 2, t, (l + r) ~/ 2 + 3, b),
];

void main() {
  group('captions', () {
    test('caption lines are recognised and named', () {
      expect(captionOf('Figure 3.2: The human heart'), 'Figure 3.2 The human heart');
      expect(captionOf('Fig. 4 Parts of a flower.'), 'Figure 4 Parts of a flower');
      expect(captionOf('DIAGRAM 1'), 'Diagram 1');
      expect(captionOf('Map 2 — Rivers of Uganda'), 'Map 2 Rivers of Uganda');
    });

    test('references in prose and ordinary lines are not captions', () {
      expect(captionOf('Figure 3 shows the heart and its chambers.'), isNull);
      expect(captionOf('Diagram 2 below is the water cycle'), isNull);
      expect(captionOf('The figure of speech used here is a simile'), isNull);
      expect(captionOf('Table 2 Results of the experiment'), isNull);
      expect(captionOf('Figure 1 ${'word ' * 30}'), isNull, reason: 'too long');
    });
  });

  group('markers', () {
    test('round-trip, with separators in names made safe', () {
      const m = DiagramMarker(
        caption: 'Figure 1 The [left] | "right" lung',
        page: 7,
        document: 'Biology | Term "1"',
      );
      final parsed = DiagramMarker.parseAll('before ${m.format()} after').single;
      expect(parsed.page, 7);
      expect(parsed.caption, 'Figure 1 The left right lung');
      expect(parsed.document, 'Biology Term 1');
    });

    test('the pointer leads with the caption and says it is the PDF page', () {
      const m = DiagramMarker(caption: 'Figure 3.2 The heart', page: 14, document: 'Bio');
      expect(
        m.pointer(),
        'Diagram: see Figure 3.2 The heart, page 14 of the PDF "Bio". '
        'Open the PDF on your phone or look in the printed copy.',
      );
      const bare = DiagramMarker(caption: DiagramMarker.kUncaptioned, page: 3, document: 'Bio');
      expect(bare.pointer(), startsWith('Diagram: see the diagram, page 3'));
    });

    test('annotatePage swaps a caption line for its marker', () {
      final a = annotatePage(
        'The heart pumps blood.\nFigure 1: The heart\nIt has four chambers.',
        page: 2,
        document: 'Bio',
        hasPicture: true,
      );
      expect(a.diagrams, 1, reason: 'the caption covers the picture');
      expect(a.text, contains('[DIAGRAM: Figure 1 The heart | page 2 of the PDF "Bio"]'));
      expect(a.text, contains('It has four chambers.'));
    });

    test('an uncaptioned picture still gets a marker; no picture, no marker', () {
      final pic = annotatePage('Plain text.', page: 5, document: 'Bio', hasPicture: true);
      expect(pic.diagrams, 1);
      expect(DiagramMarker.parseAll(pic.text).single.hasCaption, isFalse);
      final none = annotatePage('Plain text.', page: 5, document: 'Bio', hasPicture: false);
      expect(none.diagrams, 0);
      expect(none.text, 'Plain text.');
    });

    test('a marker line is never mistaken for a heading', () {
      expect(isDiagramMarkerLine('[DIAGRAM: Diagram | page 1 of the PDF "x"]'), isTrue);
    });
  });

  group('picture regions', () {
    test('line art with no text over it is a picture', () {
      expect(countPictureRegions(page(480, 640, drawing(100, 200, 380, 420)), const []), 1);
    });

    test('ink that text boxes cover is text, not a picture', () {
      final covered = [const PageBox(0.1, 0.25, 0.9, 0.7)];
      expect(countPictureRegions(page(480, 640, drawing(100, 200, 380, 420)), covered), 0);
    });

    test('blank pages, rules and the scanner edge shadow are not pictures', () {
      expect(countPictureRegions(page(480, 640, const []), const []), 0);
      expect(countPictureRegions(page(480, 640, [(40, 300, 440, 303)]), const []), 0);
      expect(countPictureRegions(page(480, 640, [(0, 0, 20, 640)]), const []), 0);
    });

    test('inkRatio tells a blank page from a printed one', () {
      expect(inkRatio(page(480, 640, const [])), lessThan(0.005));
      expect(inkRatio(page(480, 640, drawing(100, 200, 380, 420))), greaterThan(0.005));
    });
  });

  group('chunking', () {
    test('a diagram marker is never split across chunks', () {
      const marker = DiagramMarker(
        caption: 'Figure 12.4 The structure of the human heart and its valves',
        page: 88,
        document: 'Senior Two Biology Complete Notes',
      );
      for (var lead = 300; lead < 560; lead += 7) {
        final text = '${'Blood moves through the body ' * (lead ~/ 30)}'
            '${marker.format()} ${'and back to the lungs ' * 30}';
        final chunks = chunkContent(text);
        final markers = chunks.expand(DiagramMarker.parseAll).toList();
        expect(markers, hasLength(1), reason: 'lead $lead');
        expect(markers.single.page, 88);
      }
    });
  });
}
