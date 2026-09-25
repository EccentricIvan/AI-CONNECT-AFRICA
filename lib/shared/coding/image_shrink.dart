import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'html_images.dart';

// Kept apart from html_images.dart, which the project scaffold (and the
// pure-Dart tools/write_sample_projects.dart) import: this file needs
// Flutter's isolate helper.

/// Pictures wider/taller than this are shrunk; photos are re-saved as JPEG.
const kMaxImageSide = 1600;

/// Shrinks a big photo so the page stays fast on a low-end phone. Runs on a
/// background isolate. PNG/GIF/SVG with transparency or animation, and
/// anything already small, are kept as they are.
Future<PickedImage> shrinkPickedImage(PickedImage image) async {
  if (image.mime == 'image/svg+xml' || image.mime == 'image/gif') return image;
  if (image.bytes.length < 300 * 1024) return image;
  final out = await compute(_shrink, (image.bytes, image.mime));
  if (out == null) return image;
  final name = image.name.contains('.')
      ? '${image.name.substring(0, image.name.lastIndexOf('.'))}.${out.$2 == 'image/png' ? 'png' : 'jpg'}'
      : image.name;
  return PickedImage(name: name, bytes: out.$1, mime: out.$2);
}

(Uint8List, String)? _shrink((Uint8List, String) input) {
  final (bytes, mime) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var picture = img.bakeOrientation(decoded);
  final longest = picture.width > picture.height ? picture.width : picture.height;
  if (longest > kMaxImageSide) {
    picture = picture.width >= picture.height
        ? img.copyResize(picture, width: kMaxImageSide)
        : img.copyResize(picture, height: kMaxImageSide);
  }
  // Keep PNGs with transparency as PNG (logos); everything else → JPEG.
  if (mime == 'image/png' && picture.hasAlpha) {
    final png = Uint8List.fromList(img.encodePng(picture, level: 6));
    return png.length < bytes.length ? (png, 'image/png') : null;
  }
  final jpg = Uint8List.fromList(img.encodeJpg(picture, quality: 82));
  return jpg.length < bytes.length ? (jpg, 'image/jpeg') : null;
}

