import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../gamification/badge_service.dart';
import 'block_models.dart';
import 'html_generator.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class BuilderState {
  const BuilderState({
    this.started = false,
    this.projectId,
    this.doc = const WebsiteDoc(),
    this.selectedId,
    this.aiBusyBlockId,
    this.dirty = false,
  });

  final bool started;
  final int? projectId;
  final WebsiteDoc doc;
  final String? selectedId;
  final String? aiBusyBlockId;
  final bool dirty;

  SiteBlock? get selectedBlock {
    if (selectedId == null) return null;
    for (final b in doc.blocks) {
      if (b.id == selectedId) return b;
    }
    return null;
  }

  BuilderState copyWith({
    bool? started,
    int? projectId,
    WebsiteDoc? doc,
    String? selectedId,
    String? aiBusyBlockId,
    bool? dirty,
    bool clearSelection = false,
    bool clearAiBusy = false,
  }) =>
      BuilderState(
        started: started ?? this.started,
        projectId: projectId ?? this.projectId,
        doc: doc ?? this.doc,
        selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
        aiBusyBlockId:
            clearAiBusy ? null : (aiBusyBlockId ?? this.aiBusyBlockId),
        dirty: dirty ?? this.dirty,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class WebsiteBuilderNotifier extends AutoDisposeNotifier<BuilderState> {
  @override
  BuilderState build() => const BuilderState();

  void newSite(String title) {
    state = BuilderState(
      started: true,
      doc: WebsiteDoc(
        title: title.trim().isEmpty ? 'My Website' : title.trim(),
        blocks: [SiteBlock.starter(SiteBlockType.header)],
      ),
      dirty: true,
    );
  }

  void openSaved(WebsiteProject row) {
    state = BuilderState(
      started: true,
      projectId: row.id,
      doc: WebsiteDoc(
        title: row.title,
        themeColor: row.themeColor,
        blocks: WebsiteDoc.blocksFromJson(row.blocksJson),
      ),
    );
  }

  void backToStart() => state = const BuilderState();

  // ── Block operations ──────────────────────────────────────────────────────

  /// Adds a new block. [beforeId] inserts before that block (drop on a block);
  /// null appends to the end (drop on empty canvas / end zone / palette tap).
  void addBlock(SiteBlockType type, {String? beforeId}) {
    final block = SiteBlock.starter(type);
    final blocks = [...state.doc.blocks];
    final i = beforeId == null
        ? -1
        : blocks.indexWhere((b) => b.id == beforeId);
    if (i < 0) {
      blocks.add(block);
    } else {
      blocks.insert(i, block);
    }
    state = state.copyWith(
      doc: state.doc.copyWith(blocks: blocks),
      selectedId: block.id,
      dirty: true,
    );
  }

  void removeBlock(String id) {
    final blocks = state.doc.blocks.where((b) => b.id != id).toList();
    state = state.copyWith(
      doc: state.doc.copyWith(blocks: blocks),
      dirty: true,
      clearSelection: state.selectedId == id,
    );
  }

  /// [newIndex] is already adjusted for the removed item
  /// (ReorderableListView.onReorderItem semantics).
  void reorder(int oldIndex, int newIndex) {
    final blocks = [...state.doc.blocks];
    final moved = blocks.removeAt(oldIndex);
    blocks.insert(newIndex.clamp(0, blocks.length), moved);
    state = state.copyWith(
        doc: state.doc.copyWith(blocks: blocks), dirty: true);
  }

  void select(String? id) => state = id == null
      ? state.copyWith(clearSelection: true)
      : state.copyWith(selectedId: id);

  void updateBlock(String id, SiteBlock Function(SiteBlock) change) {
    final blocks = state.doc.blocks
        .map((b) => b.id == id ? change(b) : b)
        .toList();
    state = state.copyWith(
        doc: state.doc.copyWith(blocks: blocks), dirty: true);
  }

  void setTitle(String title) => state = state.copyWith(
      doc: state.doc.copyWith(title: title), dirty: true);

  void setThemeColor(String hex) => state = state.copyWith(
      doc: state.doc.copyWith(themeColor: hex), dirty: true);

  // ── AI assist ─────────────────────────────────────────────────────────────

  /// Asks the on-device model to write content for one block.
  Future<void> aiFill(String blockId) async {
    final block =
        state.doc.blocks.where((b) => b.id == blockId).firstOrNull;
    if (block == null || state.aiBusyBlockId != null) return;

    state = state.copyWith(aiBusyBlockId: blockId);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final site = state.doc.title;

      final instruction = switch (block.type) {
        SiteBlockType.header =>
          'Write a catchy website title (max 6 words), then on a new line a one-sentence subtitle.',
        SiteBlockType.text =>
          'Write one short, friendly paragraph (2-3 sentences) for this section.',
        SiteBlockType.quote =>
          'Write one short inspiring quote related to the website topic.',
        SiteBlockType.list =>
          'Write 3 short list items (one per line, no numbering or bullets).',
        _ => 'Write one short line of text.',
      };

      final response = await engine.generate(
        prompt:
            'You are helping a student build a simple website called "$site".\n'
            '$instruction\n'
            'Reply with ONLY the requested text, no explanations.\n',
        maxTokens: 120,
        temperature: 0.8,
        onToken: (_) {},
      );

      final cleaned = response.trim();
      if (cleaned.isEmpty) return;

      updateBlock(blockId, (b) {
        switch (b.type) {
          case SiteBlockType.header:
            final lines = cleaned.split('\n');
            return b.copyWith(
              text: lines.first.trim(),
              secondary: lines.length > 1 ? lines[1].trim() : b.secondary,
            );
          case SiteBlockType.list:
            final items = cleaned
                .split('\n')
                .map((l) => l.replaceFirst(RegExp(r'^[-•*\d.]+\s*'), '').trim())
                .where((l) => l.isNotEmpty)
                .toList();
            return items.isEmpty ? b : b.copyWith(items: items);
          default:
            return b.copyWith(text: cleaned);
        }
      });
    } catch (_) {
      // Model unavailable — leave the block as the student typed it.
    } finally {
      state = state.copyWith(clearAiBusy: true);
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<bool> save() async {
    final student = await ref.read(activeStudentProvider.future);
    if (student == null) return false;
    final db = ref.read(dbProvider);
    final doc = state.doc;

    if (state.projectId == null) {
      final id = await db.websiteDao.saveWebsite(
        WebsiteProjectsCompanion.insert(
          studentId: student.id,
          title: doc.title,
          themeColor: Value(doc.themeColor),
          blocksJson: Value(doc.blocksToJson()),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      state = state.copyWith(projectId: id, dirty: false);
      // Counts toward Achievements the same as any other saved project —
      // see the Creator badge and Achievements' combined project count.
      await ref.read(badgeServiceProvider).onProjectSaved(student.id);
    } else {
      await db.websiteDao.updateWebsite(
        state.projectId!,
        WebsiteProjectsCompanion(
          title: Value(doc.title),
          themeColor: Value(doc.themeColor),
          blocksJson: Value(doc.blocksToJson()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      state = state.copyWith(dirty: false);
    }
    ref.invalidate(studentWebsitesProvider(student.id));
    return true;
  }

  Future<void> deleteSaved(int id) async {
    final student = await ref.read(activeStudentProvider.future);
    final db = ref.read(dbProvider);
    await db.websiteDao.deleteWebsite(id);
    if (student != null) {
      ref.invalidate(studentWebsitesProvider(student.id));
    }
  }

  // ── Export ────────────────────────────────────────────────────────────────

  String currentHtml() => generateHtml(state.doc);

  /// Saves the generated .html through the platform file dialog.
  /// Returns the saved path, or null if the user cancelled.
  Future<String?> exportHtml() async {
    final html = currentHtml();
    final bytes = Uint8List.fromList(utf8.encode(html));
    final fileName =
        '${state.doc.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_').toLowerCase()}.html';

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export website',
      fileName: fileName.isEmpty ? 'my_website.html' : fileName,
      type: FileType.custom,
      allowedExtensions: ['html'],
      bytes: bytes,
    );
    if (path == null) return null;

    // On desktop saveFile only returns the chosen path — write it ourselves.
    // On Android the picker already wrote the bytes.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(path).writeAsBytes(bytes);
    }
    return path;
  }
}

final websiteBuilderProvider =
    AutoDisposeNotifierProvider<WebsiteBuilderNotifier, BuilderState>(
        WebsiteBuilderNotifier.new);
