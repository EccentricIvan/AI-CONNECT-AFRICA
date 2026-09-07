import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../db/otic_database.dart';
import '../../db/providers/db_provider.dart';
import '../../shared/widgets/responsive.dart';
import '../../l10n/app_locale.dart';
import '../../shared/widgets/studio_page.dart';
import 'block_models.dart';
import 'website_provider.dart';

Color _hex(String hex) {
  final ok = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex);
  return ok
      ? Color(int.parse('FF${hex.substring(1)}', radix: 16))
      : AppColors.primary;
}

// ── Screen root ───────────────────────────────────────────────────────────────

class WebsiteBuilderScreen extends ConsumerWidget {
  const WebsiteBuilderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final started = ref.watch(websiteBuilderProvider.select((s) => s.started));
    return started ? const _EditorView() : const _StartView();
  }
}

// ── Start view: saved sites + new ─────────────────────────────────────────────

class _StartView extends ConsumerWidget {
  const _StartView();

  Future<void> _newSite(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your website'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. My Farm Page'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Start building'),
          ),
        ],
      ),
    );
    if (name != null) {
      ref.read(websiteBuilderProvider.notifier).newSite(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(activeStudentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Website Builder'),
        actions: const [StudioDrawerButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newSite(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New website'),
      ),
      body: studentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (student) {
          if (student == null) {
            return const Center(child: Text('No student profile found.'));
          }
          final sitesAsync = ref.watch(studentWebsitesProvider(student.id));
          return sitesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (sites) => sites.isEmpty
                ? const _EmptyStart()
                : MaxWidth(
                    maxWidth: 760,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sites.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _SavedSiteTile(site: sites[i]),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _EmptyStart extends StatelessWidget {
  const _EmptyStart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.web,
            size: 64,
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Build your first website',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Drag blocks onto the page, fill them in, and export a real .html file that opens in any browser — all offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSiteTile extends ConsumerWidget {
  const _SavedSiteTile({required this.site});
  final WebsiteProject site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(websiteBuilderProvider.notifier);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _hex(site.themeColor).withValues(alpha: 0.15),
          child: Icon(Icons.web, color: _hex(site.themeColor)),
        ),
        title: Text(
          site.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Updated ${site.updatedAt.day}/${site.updatedAt.month}/${site.updatedAt.year}',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Delete',
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete website?'),
                content: Text('"${site.title}" will be removed.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok == true) notifier.deleteSaved(site.id);
          },
        ),
        onTap: () => notifier.openSaved(site),
      ),
    );
  }
}

// ── Editor view ───────────────────────────────────────────────────────────────

class _EditorView extends ConsumerWidget {
  const _EditorView();

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(websiteBuilderProvider.notifier).save();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Website saved!' : 'Could not save — no profile.'),
        backgroundColor: ok ? AppColors.teachColor : Colors.redAccent,
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final path = await ref.read(websiteBuilderProvider.notifier).exportHtml();
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported! Open it in a browser:\n$path'),
            backgroundColor: AppColors.teachColor,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showCode(BuildContext context, WidgetRef ref) {
    final html = ref.read(websiteBuilderProvider.notifier).currentHtml();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your website\'s HTML code'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              html,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(websiteBuilderProvider);
    final notifier = ref.read(websiteBuilderProvider.notifier);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'My websites',
          onPressed: () async {
            if (state.dirty) {
              final leave = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Leave without saving?'),
                  content: const Text('You have unsaved changes.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Stay'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Leave'),
                    ),
                  ],
                ),
              );
              if (leave != true) return;
            }
            notifier.backToStart();
          },
        ),
        title: Text(state.doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Page settings',
            onPressed: () => _openSitePanel(context),
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'View HTML code',
            onPressed: () => _showCode(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export .html',
            onPressed: () => _export(context, ref),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => _save(context, ref),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(state.dirty ? 'Save*' : 'Save'),
            ),
          ),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                const SizedBox(
                  width: 170,
                  child: _Palette(axis: Axis.vertical),
                ),
                const VerticalDivider(width: 1),
                const Expanded(child: _Canvas()),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 300,
                  child: state.selectedBlock == null
                      ? const _SitePanel()
                      : _Inspector(
                          key: ValueKey(state.selectedBlock!.id),
                          block: state.selectedBlock!,
                        ),
                ),
              ],
            )
          : const Column(
              children: [
                SizedBox(height: 84, child: _Palette(axis: Axis.horizontal)),
                Divider(height: 1),
                Expanded(child: _Canvas()),
              ],
            ),
    );
  }

  void _openSitePanel(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: _SitePanel(),
      ),
    );
  }
}

// ── Palette ───────────────────────────────────────────────────────────────────

class _Palette extends ConsumerWidget {
  const _Palette({required this.axis});
  final Axis axis;

  static const _icons = {
    SiteBlockType.header: Icons.title,
    SiteBlockType.text: Icons.notes,
    SiteBlockType.image: Icons.image_outlined,
    SiteBlockType.button: Icons.smart_button,
    SiteBlockType.list: Icons.format_list_bulleted,
    SiteBlockType.quote: Icons.format_quote,
    SiteBlockType.divider: Icons.horizontal_rule,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(websiteBuilderProvider.notifier);
    final vertical = axis == Axis.vertical;

    final items = SiteBlockType.values.map((type) {
      final chip = _PaletteChip(type: type, icon: _icons[type]!);
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Draggable<SiteBlockType>(
          data: type,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: chip),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: chip),
          // Tap also adds the block — easier on touch screens.
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => notifier.addBlock(type),
            child: chip,
          ),
        ),
      );
    }).toList();

    if (vertical) {
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              'BLOCKS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).hintColor,
                letterSpacing: 1,
              ),
            ),
          ),
          ...items,
        ],
      );
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: items,
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.type, required this.icon});
  final SiteBlockType type;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(type.label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Icon(Icons.drag_indicator, size: 14, color: Theme.of(context).hintColor),
        ],
      ),
    );
  }
}

// ── Canvas ────────────────────────────────────────────────────────────────────

class _Canvas extends ConsumerWidget {
  const _Canvas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(websiteBuilderProvider);
    final notifier = ref.read(websiteBuilderProvider.notifier);
    final blocks = state.doc.blocks;

    if (blocks.isEmpty) {
      return DragTarget<SiteBlockType>(
        onAcceptWithDetails: (d) => notifier.addBlock(d.data),
        builder: (context, candidates, _) => Container(
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(
              color: candidates.isNotEmpty
                  ? AppColors.primary
                  : Theme.of(context).dividerColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              'Drag a block here to start\n(or tap one in the palette)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: MaxWidth(
        maxWidth: 720,
        child: Column(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                buildDefaultDragHandles: false,
                itemCount: blocks.length,
                onReorderItem: notifier.reorder,
                itemBuilder: (context, i) {
                  final block = blocks[i];
                  return _CanvasItem(
                    key: ValueKey(block.id),
                    block: block,
                    index: i,
                    themeColor: _hex(state.doc.themeColor),
                    selected: state.selectedId == block.id,
                    aiBusy: state.aiBusyBlockId == block.id,
                  );
                },
              ),
            ),
            // End drop zone — drop here to add at the bottom.
            DragTarget<SiteBlockType>(
              onAcceptWithDetails: (d) => notifier.addBlock(d.data),
              builder: (context, candidates, _) => Container(
                height: 56,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: candidates.isNotEmpty
                        ? AppColors.primary
                        : Theme.of(context).dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Drop new blocks here',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasItem extends ConsumerWidget {
  const _CanvasItem({
    super.key,
    required this.block,
    required this.index,
    required this.themeColor,
    required this.selected,
    required this.aiBusy,
  });

  final SiteBlock block;
  final int index;
  final Color themeColor;
  final bool selected;
  final bool aiBusy;

  bool get _aiCapable => switch (block.type) {
    SiteBlockType.header ||
    SiteBlockType.text ||
    SiteBlockType.quote ||
    SiteBlockType.list => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(websiteBuilderProvider.notifier);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    // Dropping a palette block onto an existing block inserts above it.
    return DragTarget<SiteBlockType>(
      onAcceptWithDetails: (d) => notifier.addBlock(d.data, beforeId: block.id),
      builder: (context, candidates, _) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (candidates.isNotEmpty)
              Container(
                height: 4,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            InkWell(
              onTap: () {
                notifier.select(block.id);
                if (!isWide) _openInspectorSheet(context, block.id);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppColors.primary : Theme.of(context).dividerColor,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                        Text(
                          block.type.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                        const Spacer(),
                        if (_aiCapable)
                          aiBusy
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                    color: AppColors.createColor,
                                  ),
                                  tooltip: tr(context, 'Ask AI'),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => notifier.aiFill(block.id),
                                ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Remove block',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => notifier.removeBlock(block.id),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: _BlockPreview(
                        block: block,
                        themeColor: themeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openInspectorSheet(BuildContext context, String blockId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Consumer(
          builder: (context, ref, _) {
            final b = ref.watch(
              websiteBuilderProvider.select(
                (s) => s.doc.blocks.where((x) => x.id == blockId).firstOrNull,
              ),
            );
            if (b == null) return const SizedBox(height: 80);
            return _Inspector(key: ValueKey(b.id), block: b);
          },
        ),
      ),
    );
  }
}

// ── WYSIWYG block preview ─────────────────────────────────────────────────────

class _BlockPreview extends StatelessWidget {
  const _BlockPreview({required this.block, required this.themeColor});
  final SiteBlock block;
  final Color themeColor;

  TextAlign get _ta => switch (block.align) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    _ => TextAlign.left,
  };

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case SiteBlockType.header:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: themeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: block.align == 'center'
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                block.text,
                textAlign: _ta,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (block.secondary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  block.secondary,
                  textAlign: _ta,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ],
          ),
        );
      case SiteBlockType.text:
        return Text(block.text, textAlign: _ta);
      case SiteBlockType.image:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            border: Border.all(color: themeColor, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(Icons.image_outlined, color: themeColor, size: 32),
              if (block.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    block.text,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        );
      case SiteBlockType.button:
        return Align(
          alignment: switch (block.align) {
            'center' => Alignment.center,
            'right' => Alignment.centerRight,
            _ => Alignment.centerLeft,
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: themeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              block.text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      case SiteBlockType.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  block.text,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ...block.items.map(
              (i) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: themeColor)),
                    Expanded(child: Text(i)),
                  ],
                ),
              ),
            ),
          ],
        );
      case SiteBlockType.quote:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(left: BorderSide(color: themeColor, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block.text,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              if (block.secondary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '— ${block.secondary}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      case SiteBlockType.divider:
        return const Divider(thickness: 2);
    }
  }
}

// ── Inspector (edit selected block) ───────────────────────────────────────────

class _Inspector extends ConsumerWidget {
  const _Inspector({super.key, required this.block});
  final SiteBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(websiteBuilderProvider.notifier);

    final fields = <Widget>[
      Text(
        'Edit ${block.type.label}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
    ];

    void addField(
      String label,
      String initial,
      void Function(String) onChanged, {
      int maxLines = 1,
    }) {
      fields.addAll([
        TextFormField(
          initialValue: initial,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
      ]);
    }

    switch (block.type) {
      case SiteBlockType.header:
        addField(
          'Title',
          block.text,
          (v) => notifier.updateBlock(block.id, (b) => b.copyWith(text: v)),
        );
        addField(
          'Subtitle',
          block.secondary,
          (v) =>
              notifier.updateBlock(block.id, (b) => b.copyWith(secondary: v)),
        );
      case SiteBlockType.text:
        addField(
          'Text',
          block.text,
          (v) => notifier.updateBlock(block.id, (b) => b.copyWith(text: v)),
          maxLines: 5,
        );
      case SiteBlockType.image:
        addField(
          'Caption',
          block.text,
          (v) => notifier.updateBlock(block.id, (b) => b.copyWith(text: v)),
        );
        addField(
          'Describe the image',
          block.secondary,
          (v) =>
              notifier.updateBlock(block.id, (b) => b.copyWith(secondary: v)),
        );
      case SiteBlockType.button:
        addField(
          'Button label',
          block.text,
          (v) => notifier.updateBlock(block.id, (b) => b.copyWith(text: v)),
        );
        addField(
          'Link (https://…)',
          block.secondary,
          (v) =>
              notifier.updateBlock(block.id, (b) => b.copyWith(secondary: v)),
        );
      case SiteBlockType.list:
        addField(
          'List title',
          block.text,
          (v) => notifier.updateBlock(block.id, (b) => b.copyWith(text: v)),
        );
        addField(
          'Items (one per line)',
          block.items.join('\n'),
          (v) => notifier.updateBlock(
            block.id,
            (b) => b.copyWith(
              items: v.split('\n').where((l) => l.trim().isNotEmpty).toList(),
            ),
          ),
          maxLines: 6,
        );
      case SiteBlockType.quote:
        addField(
          'Quote',
          block.text,
          (v) => notifier.updateBlock(block.id, (b) => b.copyWith(text: v)),
          maxLines: 3,
        );
        addField(
          'Author',
          block.secondary,
          (v) =>
              notifier.updateBlock(block.id, (b) => b.copyWith(secondary: v)),
        );
      case SiteBlockType.divider:
        fields.add(
          Text(
            'A divider has no settings.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
    }

    if (block.type != SiteBlockType.divider &&
        block.type != SiteBlockType.image) {
      fields.addAll([
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'left',
              icon: Icon(Icons.format_align_left, size: 16),
            ),
            ButtonSegment(
              value: 'center',
              icon: Icon(Icons.format_align_center, size: 16),
            ),
            ButtonSegment(
              value: 'right',
              icon: Icon(Icons.format_align_right, size: 16),
            ),
          ],
          selected: {block.align},
          onSelectionChanged: (s) =>
              notifier.updateBlock(block.id, (b) => b.copyWith(align: s.first)),
        ),
      ]);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: fields,
    );
  }
}

// ── Site panel (title + theme) ────────────────────────────────────────────────

class _SitePanel extends ConsumerWidget {
  const _SitePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(websiteBuilderProvider);
    final notifier = ref.read(websiteBuilderProvider.notifier);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Page settings',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('title_${state.projectId ?? 'new'}'),
          initialValue: state.doc.title,
          decoration: const InputDecoration(
            labelText: 'Website title',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: notifier.setTitle,
        ),
        const SizedBox(height: 16),
        const Text(
          'Theme color',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: siteThemeColors.entries.map((e) {
            final selected = state.doc.themeColor == e.value;
            return Tooltip(
              message: e.key,
              child: InkWell(
                onTap: () => notifier.setThemeColor(e.value),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _hex(e.value),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Tip: tap any block on the page to edit it. Drag blocks from the palette onto the page, or drop them on top of a block to insert above it.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
