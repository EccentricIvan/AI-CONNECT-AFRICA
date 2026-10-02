import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../db/providers/db_provider.dart';
import '../../features/learn/notes_quiz.dart';
import '../custom_subject_service.dart';
import '../ocr/ocr_engine.dart';
import '../pdf/pdf_page_extractor.dart';
import 'note_pdf_store.dart';
import 'note_quiz_store.dart';

/// Pages shorter than this are headings or captions, not worth a question.
const _minPageChars = 120;

/// Writes one quiz question per page of each of this device's note PDFs,
/// in the background, as soon as the PDF is uploaded — so a learner who
/// opens Quiz gets questions instantly instead of waiting on the model.
///
/// - Only this device's own PDFs: a received note is signed by its teacher
///   and can't take new rows. Students get the questions on sync.
/// - Reads the kept PDF page by page (embedded text, OCR for scans) and
///   saves the next page to do after each one, so closing the app loses at
///   most one page; [resumePending] carries on at the next launch, and also
///   covers PDFs uploaded before this existed.
/// - Waits while the chat is answering. Both share the one brain, which
///   runs one request at a time, so a chat message sent mid-question waits
///   for that question to finish.
/// - When the engine fails (it answers with a stock sentence rather than
///   throwing) the page is retried later, never skipped.
class NoteQuizBuilder {
  NoteQuizBuilder(this._ref);

  final Ref _ref;
  final _queue = Queue<NotePdf>();
  bool _running = false;
  Timer? _retry;

  static const retryAfter = Duration(minutes: 2);

  static String progressKey(NotePdf p) =>
      'note_quiz_next:${p.subjectId}|${p.documentTitle}|${p.sha256}';

  /// Queues [pdf]. [fresh] (a new upload) drops its earlier questions and
  /// starts again from page 1.
  Future<void> enqueue(NotePdf pdf, {bool fresh = false}) async {
    if (pdf.classGroupUuid != null) return;
    if (fresh) {
      await _ref
          .read(dbProvider)
          .topicResourceDao
          .deleteQuizRows(
            subjectId: pdf.subjectId,
            documentTitle: pdf.documentTitle,
          );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(progressKey(pdf), 1);
    }
    if (!_queue.any((q) => progressKey(q) == progressKey(pdf))) {
      _queue.add(pdf);
    }
    unawaited(_pump());
  }

  /// Queues every own PDF that still has pages without a question.
  Future<void> resumePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pdfs = await _ref.read(notePdfStoreProvider).recorded(ownOnly: true);
      for (final p in pdfs) {
        final next = prefs.getInt(progressKey(p)) ?? 1;
        if (p.pages == 0 || next <= p.pages) await enqueue(p);
      }
    } catch (e) {
      debugPrint('Note quiz resume failed: $e');
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final ok = await _build(_queue.first);
        if (!ok) {
          _retry?.cancel();
          _retry = Timer(retryAfter, () => unawaited(_pump()));
          return;
        }
        _queue.removeFirst();
      }
    } finally {
      _running = false;
    }
  }

  /// False when the engine is unavailable and [pdf] must be tried again.
  Future<bool> _build(NotePdf pdf) async {
    final InferenceEngine brain;
    try {
      brain = await _ref.read(engineLoadedProvider.future);
    } catch (e) {
      debugPrint('Note quiz: brain unavailable, retrying later: $e');
      return false;
    }
    if (brain.isDemo || !brain.isReady) return false;

    final store = _ref.read(notePdfStoreProvider);
    final file = await store.fileFor(pdf.sha256);
    if (file == null) return true;

    final db = _ref.read(dbProvider);
    final prefs = await SharedPreferences.getInstance();
    final key = progressKey(pdf);
    final generator = NotesQuizGenerator(brain);
    var subject = pdf.subjectId;
    try {
      subject =
          (await _ref.read(subjectByIdProvider(pdf.subjectId).future))?.name ??
          subject;
    } catch (_) {}
    OcrEngine? ocr;
    try {
      ocr = await _ref.read(ocrEngineProvider.future);
    } catch (_) {}

    final PdfPageSource source;
    try {
      source = await PdfrxPageSource.open(
        await file.readAsBytes(),
        name: 'quiz-${pdf.sha256}',
      );
    } catch (e) {
      debugPrint('Note quiz: could not open "${pdf.documentTitle}": $e');
      return true;
    }
    try {
      final pages = source.pageCount;
      for (var page = prefs.getInt(key) ?? 1; page <= pages; page++) {
        if (!await _stillRecorded(store, pdf)) return true;
        final text = await readablePageText(source, page, ocr: ocr);
        if (text.length >= _minPageChars) {
          await _chatIdle();
          final started = DateTime.now();
          final r = await generator.tryPassage(text, subject: subject);
          if (r.engineFailed) return false;
          final q = r.question;
          if (q != null && await _stillRecorded(store, pdf)) {
            await db.topicResourceDao.insertQuizRow(
              subjectId: pdf.subjectId,
              documentTitle: pdf.documentTitle,
              content: NoteQuizStore.format(q, page),
              termMarker: await _termOf(pdf),
            );
          }
          debugPrint(
            'Note quiz: "${pdf.documentTitle}" page $page/$pages '
            '${q == null ? 'no question' : 'saved'} in '
            '${DateTime.now().difference(started).inMilliseconds} ms',
          );
        }
        await prefs.setInt(key, page + 1);
      }
      return true;
    } finally {
      await source.close();
    }
  }

  /// False once the note was deleted or re-uploaded as another file.
  Future<bool> _stillRecorded(NotePdfStore store, NotePdf pdf) async {
    final own = await store.recorded(subjectId: pdf.subjectId, ownOnly: true);
    return own.any(
      (p) => p.sha256 == pdf.sha256 && p.documentTitle == pdf.documentTitle,
    );
  }

  /// The term of the note's PDF marker, so its questions file with it.
  Future<int> _termOf(NotePdf pdf) async {
    final db = _ref.read(dbProvider);
    final row =
        await (db.select(db.topicResources)
              ..where((t) => t.subjectId.equals(pdf.subjectId))
              ..where((t) => t.documentTitle.equals(pdf.documentTitle))
              ..where((t) => t.classGroupUuid.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row?.termMarker ?? 0;
  }

  /// Returns once the chat has not been answering for a few seconds.
  Future<void> _chatIdle() async {
    DateTime? busyAt;
    while (true) {
      final busy = _ref.read(chatProvider).valueOrNull?.isGenerating ?? false;
      if (busy) {
        busyAt = DateTime.now();
      } else if (busyAt == null ||
          DateTime.now().difference(busyAt) >= const Duration(seconds: 3)) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  void dispose() => _retry?.cancel();
}

final noteQuizBuilderProvider = Provider<NoteQuizBuilder>((ref) {
  final builder = NoteQuizBuilder(ref);
  ref.onDispose(builder.dispose);
  return builder;
});

final noteQuizStoreProvider = Provider<NoteQuizStore>(
  (ref) => NoteQuizStore(ref.watch(dbProvider)),
);
