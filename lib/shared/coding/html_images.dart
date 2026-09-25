import 'dart:convert';
import 'dart:typed_data';

import 'interactive_html.dart' show escapeHtml;

/// A picture the student added, embedded as a data URI while they edit so
/// the live preview shows it with no file server behind it. [extractImages]
/// turns these back into real files when the project is saved.
class PickedImage {
  const PickedImage({required this.name, required this.bytes, required this.mime});
  final String name;
  final Uint8List bytes;
  final String mime;

  String get dataUri => 'data:$mime;base64,${base64Encode(bytes)}';

  /// Alt text from the file name: "my_shop-front.jpg" → "my shop front".
  String get altText {
    final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final words = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return words.isEmpty ? 'Picture' : words;
  }

  static String? mimeFor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      _ => null,
    };
  }
}

/// Largest picture accepted before shrinking (a raw phone photo is 2–8 MB).
const kMaxImageBytes = 20 * 1024 * 1024;

/// While the coder model edits the page, embedded pictures are swapped for
/// short placeholder paths: a photo's base64 would otherwise fill the
/// model's whole prompt (and come back truncated). [restore] puts them back.
({String text, String Function(String edited) restore}) maskEmbeddedImages(String html) {
  final byToken = <String, String>{};
  final byData = <String, String>{};
  var n = 1;
  final masked = html.replaceAllMapped(_dataUriRe, (m) {
    final data = m.group(0)!;
    final existing = byData[data];
    if (existing != null) return existing;
    final ext = m.group(1)!.split('/').last.replaceAll('+xml', '');
    final token = 'images/otic-embedded-${n++}.$ext';
    byData[data] = token;
    byToken[token] = data;
    return token;
  });
  String restore(String edited) {
    var out = edited;
    byToken.forEach((token, data) => out = out.replaceAll(token, data));
    return out;
  }

  return (text: masked, restore: restore);
}

/// One `<img>` already on the page, for "replace this picture".
class PageImage {
  const PageImage({required this.index, required this.src, required this.alt});
  final int index;
  final String src;
  final String alt;

  String get label {
    if (alt.trim().isNotEmpty) return alt.trim();
    if (src.startsWith('data:')) return 'Picture ${index + 1} (yours)';
    final file = src.split('/').last.split('?').first;
    return file.isEmpty ? 'Picture ${index + 1}' : file;
  }
}

final _imgRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _srcRe = RegExp(r'''\bsrc\s*=\s*(["'])(.*?)\1''', caseSensitive: false, dotAll: true);
final _altRe = RegExp(r'''\balt\s*=\s*(["'])(.*?)\1''', caseSensitive: false, dotAll: true);

List<PageImage> listPageImages(String html) {
  final out = <PageImage>[];
  var i = 0;
  for (final m in _imgRe.allMatches(html)) {
    final tag = m.group(0)!;
    out.add(PageImage(
      index: i++,
      src: _srcRe.firstMatch(tag)?.group(2) ?? '',
      alt: _altRe.firstMatch(tag)?.group(2) ?? '',
    ));
  }
  return out;
}

/// Swaps the [index]th `<img>`'s picture for [image], keeping its classes and
/// size so the layout stays as designed.
String replacePageImage(String html, int index, PickedImage image) {
  var i = 0;
  return html.replaceAllMapped(_imgRe, (m) {
    if (i++ != index) return m.group(0)!;
    var tag = m.group(0)!;
    tag = _srcRe.hasMatch(tag)
        ? tag.replaceFirst(_srcRe, 'src="${image.dataUri}"')
        : tag.replaceFirst(RegExp(r'<img', caseSensitive: false), '<img src="${image.dataUri}"');
    final alt = 'alt="${escapeHtml(image.altText)}"';
    tag = _altRe.hasMatch(tag)
        ? tag.replaceFirst(_altRe, alt)
        : tag.replaceFirst(RegExp(r'<img', caseSensitive: false), '<img $alt');
    return tag;
  });
}

const _galleryStart = '<!-- otic-gallery -->';
const _galleryEnd = '<!-- /otic-gallery -->';

/// Adds [images] to a "Gallery" section (created before the footer the
/// first time), styled to fit any template.
String addToGallery(String html, List<PickedImage> images, {String heading = 'Gallery'}) {
  if (images.isEmpty) return html;
  final figures = StringBuffer();
  for (final img in images) {
    final alt = escapeHtml(img.altText);
    figures.writeln('    <figure><img src="${img.dataUri}" alt="$alt" loading="lazy">'
        '<figcaption>$alt</figcaption></figure>');
  }

  final start = html.indexOf(_galleryStart);
  final end = html.indexOf(_galleryEnd);
  if (start >= 0 && end > start) {
    const gridClose = '  </div>\n</section>\n';
    final close = html.lastIndexOf(gridClose, end);
    if (close > start) {
      return '${html.substring(0, close)}$figures${html.substring(close)}';
    }
  }

  final section = StringBuffer()
    ..writeln(_galleryStart)
    ..writeln('<style>.otic-gallery{max-width:1100px;margin:48px auto;padding:0 20px}'
        '.otic-gallery h2{text-align:center;margin-bottom:20px}'
        '.otic-gallery-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}'
        '.otic-gallery figure{margin:0;border-radius:14px;overflow:hidden;background:#fff;'
        'box-shadow:0 6px 20px rgba(15,23,42,.08)}'
        '.otic-gallery img{width:100%;height:200px;object-fit:cover;display:block;transition:transform .3s}'
        '.otic-gallery figure:hover img{transform:scale(1.04)}'
        '.otic-gallery figcaption{padding:10px 12px;font-size:.9rem;color:#4b5563;text-transform:capitalize}</style>')
    ..writeln('<section class="otic-gallery" id="gallery">')
    ..writeln('  <h2>${escapeHtml(heading)}</h2>')
    ..writeln('  <div class="otic-gallery-grid">')
    ..write(figures)
    ..writeln('  </div>')
    ..writeln('</section>')
    ..writeln(_galleryEnd);

  final lower = html.toLowerCase();
  var at = lower.lastIndexOf('<footer');
  if (at < 0) at = lower.lastIndexOf('</body>');
  if (at < 0) return '$html\n$section';
  return '${html.substring(0, at)}$section${html.substring(at)}';
}

/// Puts [image] in as the page's logo: replaces the first `<img>` in the
/// header/nav, or adds one at the start of it.
String setLogo(String html, PickedImage image) {
  final lower = html.toLowerCase();
  var start = lower.indexOf('<header');
  if (start < 0) start = lower.indexOf('<nav');
  if (start < 0) return html;
  final tagEnd = html.indexOf('>', start);
  if (tagEnd < 0) return html;
  final closeName = lower.startsWith('<header', start) ? '</header>' : '</nav>';
  final close = lower.indexOf(closeName, tagEnd);
  final region = close < 0 ? '' : html.substring(tagEnd + 1, close);
  final firstImg = _imgRe.firstMatch(region);
  if (firstImg != null) {
    final before = listPageImages(html.substring(0, tagEnd + 1)).length;
    return replacePageImage(html, before, image);
  }
  final logo = '<img src="${image.dataUri}" alt="${escapeHtml(image.altText)}" '
      'style="height:44px;width:auto;border-radius:8px;vertical-align:middle;margin-right:10px">';
  return '${html.substring(0, tagEnd + 1)}$logo${html.substring(tagEnd + 1)}';
}

final _dataUriRe = RegExp(
  r'''data:(image/(?:png|jpeg|gif|webp|svg\+xml));base64,([A-Za-z0-9+/=]+)''',
);

/// Saved projects keep pictures as real files: every embedded image in
/// [source] is replaced by `<folder>/<namePrefix>-N.<ext>` and returned in
/// `files`, keyed by file name only (the caller decides where the folder
/// lives). Identical images share one file.
({String text, Map<String, Uint8List> files}) extractImages(
  String source, {
  String folder = 'images',
  String namePrefix = 'picture',
}) {
  final files = <String, Uint8List>{};
  final byData = <String, String>{};
  var n = 1;
  final out = source.replaceAllMapped(_dataUriRe, (m) {
    final mime = m.group(1)!;
    final data = m.group(2)!;
    final existing = byData[data];
    if (existing != null) return existing;
    final ext = switch (mime) {
      'image/jpeg' => 'jpg',
      'image/svg+xml' => 'svg',
      _ => mime.split('/').last,
    };
    Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } catch (_) {
      return m.group(0)!;
    }
    final name = '$namePrefix-${n++}.$ext';
    files[name] = bytes;
    final rel = '$folder/$name';
    byData[data] = rel;
    return rel;
  });
  return (text: out, files: files);
}
