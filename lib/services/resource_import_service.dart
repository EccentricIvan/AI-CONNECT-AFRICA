import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/tables/topic_resources_table.dart';
import 'offline_storage_service.dart';
import 'resource_text_extractor.dart';

/// Turns an uploaded file into retrievable knowledge, end to end and offline.
///
///     file bytes → text → sections → ~500-char chunks → topic_resources
///
/// ## Why the teacher is not asked to file each topic
///
/// A textbook chapter is not one topic, and asking a teacher to paste each
/// section separately under a topic name is work no one will do twice. So the
/// document's own structure is used: [splitIntoSections] finds its headings and
/// each becomes a `topic_key`. A retrieval for "acid-base balances" then lands
/// on the pages about acid-base balances rather than on the whole book.
///
/// When a document has no detectable headings the whole file becomes one
/// section named after the file. That is a worse index, not a failure — the
/// material is still retrievable, just at document granularity.
class ResourceImportService {
  const ResourceImportService(this._storage);

  final OfflineStorageService _storage;

  /// Reads [path] and imports it into [subjectId].
  Future<ImportReport> importFile({
    required String path,
    required String subjectId,
    int termMarker = kAllTermsMarker,
    String? topicKeyOverride,
  }) async {
    final file = File(path);
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      return ImportReport.failed(_baseName(path), 'That file could not be opened ($e).');
    }
    return importBytes(
      fileName: _baseName(path),
      bytes: bytes,
      subjectId: subjectId,
      termMarker: termMarker,
      topicKeyOverride: topicKeyOverride,
    );
  }

  /// Imports already-read [bytes]. Split out from [importFile] so the whole
  /// pipeline is testable without touching the filesystem.
  Future<ImportReport> importBytes({
    required String fileName,
    required Uint8List bytes,
    required String subjectId,
    int termMarker = kAllTermsMarker,
    String? topicKeyOverride,
  }) async {
    final extracted = extractResourceText(fileName, bytes);
    if (!extracted.ok) {
      return ImportReport.failed(
        fileName,
        extracted.failure ?? 'No text could be read from that file.',
      );
    }

    final docTitle = _stripExtension(fileName);
    final sections = topicKeyOverride != null
        ? [ResourceSection(title: docTitle, body: extracted.text)]
        : splitIntoSections(extracted.text, fallbackTitle: docTitle);

    var chunks = 0;
    final topics = <String>[];
    for (final section in sections) {
      // One resource_title per section, prefixed by the document, so a teacher
      // scanning the list sees which file a section came from and deleting by
      // the document title removes the whole import.
      final title = section.title == docTitle
          ? docTitle
          : '$docTitle — ${section.title}';

      final written = await _storage.insertTopicResource(
        subjectId: subjectId,
        topicKey: topicKeyOverride ?? section.title,
        resourceTitle: title,
        content: section.body,
        termMarker: termMarker,
      );
      if (written > 0) {
        chunks += written;
        topics.add(section.title);
      }
    }

    if (chunks == 0) {
      return ImportReport.failed(
        fileName,
        'That file was read but had no usable text in it.',
      );
    }

    return ImportReport(
      fileName: fileName,
      documentTitle: docTitle,
      format: extracted.format,
      chunkCount: chunks,
      topics: topics,
      wordCount: _countWords(extracted.text),
    );
  }

  /// Imports typed or pasted text — the path for a teacher with no file.
  Future<ImportReport> importText({
    required String title,
    required String content,
    required String subjectId,
    int termMarker = kAllTermsMarker,
    String? topicKeyOverride,
  }) async {
    final body = normalizeExtractedText(content);
    if (body.trim().isEmpty) {
      return ImportReport.failed(title, 'There is no text to save.');
    }
    final written = await _storage.insertTopicResource(
      subjectId: subjectId,
      topicKey: topicKeyOverride ?? title,
      resourceTitle: title,
      content: body,
      termMarker: termMarker,
    );
    if (written == 0) {
      return ImportReport.failed(title, 'That note could not be saved.');
    }
    return ImportReport(
      fileName: title,
      documentTitle: title,
      format: 'text',
      chunkCount: written,
      topics: [title],
      wordCount: _countWords(body),
    );
  }

  /// Removes everything imported from one document.
  Future<int> removeDocument(String documentTitle, {String? subjectId}) {
    return _storage.deleteTopicResourceByTitle(
      documentTitle,
      subjectId: subjectId,
    );
  }
}

/// Outcome of one import, phrased for a teacher.
///
/// Reporting per file is the feature, not a nicety: a teacher who uploads a
/// scanned textbook and sees nothing happen has no way to know the file was
/// images, and would reasonably conclude the app is broken.
class ImportReport {
  const ImportReport({
    required this.fileName,
    required this.documentTitle,
    required this.format,
    required this.chunkCount,
    required this.topics,
    required this.wordCount,
  }) : failure = null;

  const ImportReport.failed(this.fileName, this.failure)
      : documentTitle = '',
        format = '',
        chunkCount = 0,
        topics = const [],
        wordCount = 0;

  final String fileName;
  final String documentTitle;
  final String format;

  /// Internal detail — never shown to a teacher. [wordCount] is the
  /// teacher-facing size.
  final int chunkCount;

  /// Section names this document was split into.
  final List<String> topics;

  final int wordCount;
  final String? failure;

  bool get ok => failure == null && chunkCount > 0;
}

// ── Sectioning ───────────────────────────────────────────────────────────

/// One retrievable section of a document.
class ResourceSection {
  const ResourceSection({required this.title, required this.body});
  final String title;
  final String body;
}

/// Splits [text] at its headings so each becomes its own retrievable topic.
///
/// Returns a single section named [fallbackTitle] when no headings are found —
/// which is the common case for a page of typed notes, and correct for it.
List<ResourceSection> splitIntoSections(
  String text, {
  required String fallbackTitle,
  int minSectionChars = 120,
}) {
  final lines = text.split('\n');
  final sections = <ResourceSection>[];
  var currentTitle = fallbackTitle;
  final buffer = StringBuffer();

  void flush() {
    final body = buffer.toString().trim();
    buffer.clear();
    if (body.isEmpty) return;
    // A "section" shorter than a sentence or two is a stray heading, not a
    // topic. Fold it into the previous one rather than indexing a fragment.
    if (body.length < minSectionChars && sections.isNotEmpty) {
      final last = sections.removeLast();
      sections.add(ResourceSection(
        title: last.title,
        body: '${last.body}\n\n$currentTitle\n$body'.trim(),
      ));
      return;
    }
    sections.add(ResourceSection(title: currentTitle, body: body));
  }

  for (final line in lines) {
    if (looksLikeHeading(line)) {
      flush();
      currentTitle = _cleanHeading(line);
      continue;
    }
    buffer.writeln(line);
  }
  flush();

  if (sections.isEmpty) {
    final body = text.trim();
    if (body.isEmpty) return const [];
    return [ResourceSection(title: fallbackTitle, body: body)];
  }
  return sections;
}

/// True when [line] reads as a heading rather than as prose.
///
/// Deliberately conservative. A false positive fragments a topic into pieces
/// too small to answer from; a false negative merely leaves the section
/// coarser. Coarse is recoverable, fragmented is not.
bool looksLikeHeading(String line) {
  final t = line.trim();
  if (t.isEmpty || t.length > 80) return false;
  // Prose ends in punctuation; headings almost never do.
  if (RegExp(r'[.,;:]$').hasMatch(t)) return false;
  // A heading is a few words, not a paragraph.
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || words.length > 12) return false;

  // "3.", "3.1", "Chapter 4", "Unit 2", "Topic 5", "Lesson 1:"
  if (RegExp(
    r'^(chapter|unit|topic|lesson|section|part)\s+\d+',
    caseSensitive: false,
  ).hasMatch(t)) {
    return true;
  }
  if (RegExp(r'^\d+(\.\d+)*[.)]?\s+\S').hasMatch(t) && words.length <= 10) {
    return true;
  }
  // Markdown headings.
  if (RegExp(r'^#{1,6}\s+\S').hasMatch(t)) return true;

  // ALL CAPS line with at least two letters.
  final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length >= 2 && letters == letters.toUpperCase()) return true;

  return false;
}

String _cleanHeading(String line) {
  var t = line.trim();
  t = t.replaceAll(RegExp(r'^#{1,6}\s*'), '');
  t = t.replaceAll(RegExp(r'^\d+(\.\d+)*[.)]?\s*'), '');
  t = t.replaceAll(RegExp(r'[:\-–—\s]+$'), '');
  return t.trim().isEmpty ? line.trim() : t.trim();
}

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

String _stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  return base.replaceAll('_', ' ').replaceAll('-', ' ').trim();
}

int _countWords(String text) =>
    RegExp(r'\S+').allMatches(text).length;

// ── Provider ─────────────────────────────────────────────────────────────

final resourceImportServiceProvider = Provider<ResourceImportService>((ref) {
  return ResourceImportService(ref.watch(offlineStorageServiceProvider));
});

/// Debug helper: log what an import produced without a UI.
void debugLogImport(ImportReport report) {
  debugPrint(
    report.ok
        ? 'Imported ${report.fileName}: ${report.topics.length} topics, '
            '${report.wordCount} words'
        : 'Import failed for ${report.fileName}: ${report.failure}',
  );
}
