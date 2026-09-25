import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_locale.dart';
import '../../../shared/coding/html_images.dart';
import '../../../shared/coding/image_shrink.dart';
import '../../../shared/coding/quick_style_edit.dart';

/// Row above a builder's studio: where the project is saved, plus Save,
/// Pictures, Style and Open in Projects.
class ProjectToolsBar extends StatelessWidget {
  const ProjectToolsBar({
    super.key,
    required this.savedLabel,
    required this.saving,
    required this.onSave,
    required this.onPictures,
    required this.onStyle,
    required this.onOpenProjects,
  });

  /// "Projects › Websites › my-bakery", or null before the first save.
  final String? savedLabel;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onPictures;
  final VoidCallback onStyle;
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final saved = savedLabel;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ac.border),
      ),
      child: Row(
        children: [
          Icon(
            saved == null ? Icons.folder_outlined : Icons.folder_rounded,
            size: 18,
            color: saved == null ? ac.textSecondary : AppColors.brandCyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              saved ?? tr(context, 'Not saved yet'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
          ),
          _ToolButton(
            icon: Icons.image_outlined,
            label: tr(context, 'Pictures'),
            onTap: onPictures,
          ),
          _ToolButton(
            icon: Icons.palette_outlined,
            label: tr(context, 'Style'),
            onTap: onStyle,
          ),
          _ToolButton(
            icon: saving ? Icons.hourglass_top_rounded : Icons.save_outlined,
            label: tr(context, 'Save'),
            onTap: saving ? null : onSave,
          ),
          if (saved != null)
            IconButton(
              tooltip: tr(context, 'Open in Projects'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: onOpenProjects,
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    if (narrow) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, size: 20),
        onPressed: onTap,
      );
    }
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// ── Pictures ────────────────────────────────────────────────────────────────

/// Lets the student pick pictures and choose where they go. Returns the new
/// page HTML, or null when nothing changed.
Future<String?> showAddPicturesFlow(BuildContext context, String html) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'],
      allowMultiple: true,
      withData: true,
    );
  } catch (_) {
    if (context.mounted) {
      _snack(context, tr(context, "Couldn't open your pictures. Try again."));
    }
    return null;
  }
  if (picked == null || picked.files.isEmpty || !context.mounted) return null;

  final images = <PickedImage>[];
  var tooBig = 0;
  for (final f in picked.files) {
    final bytes = f.bytes;
    final mime = PickedImage.mimeFor(f.name);
    if (bytes == null || mime == null) continue;
    if (bytes.length > kMaxImageBytes) {
      tooBig++;
      continue;
    }
    images.add(await shrinkPickedImage(PickedImage(name: f.name, bytes: bytes, mime: mime)));
  }
  if (tooBig > 0 && context.mounted) {
    _snack(
      context,
      trFill(context, '{n} picture(s) were over 20 MB and were skipped.', {'n': '$tooBig'}),
    );
  }
  if (images.isEmpty || !context.mounted) return null;

  final onPage = listPageImages(html);
  final choice = await showModalBottomSheet<_PictureChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _PicturePlacementSheet(images: images, onPage: onPage),
  );
  if (choice == null || !context.mounted) return null;
  return switch (choice.kind) {
    _Placement.gallery => addToGallery(html, images, heading: tr(context, 'Gallery')),
    _Placement.logo => setLogo(html, images.first),
    _Placement.replace => replacePageImage(html, choice.replaceIndex!, images.first),
  };
}

enum _Placement { gallery, logo, replace }

class _PictureChoice {
  const _PictureChoice(this.kind, [this.replaceIndex]);
  final _Placement kind;
  final int? replaceIndex;
}

class _PicturePlacementSheet extends StatelessWidget {
  const _PicturePlacementSheet({required this.images, required this.onPage});
  final List<PickedImage> images;
  final List<PageImage> onPage;

  @override
  Widget build(BuildContext context) {
    final one = images.length == 1;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              one
                  ? tr(context, 'Where should this picture go?')
                  : trFill(context, 'Where should these {n} pictures go?',
                      {'n': '${images.length}'}),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: images[i].mime == 'image/svg+xml'
                      ? Container(
                          width: 72,
                          color: Colors.black12,
                          child: const Icon(Icons.image_outlined),
                        )
                      : Image.memory(images[i].bytes, width: 72, height: 72, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: Text(tr(context, 'Add to a picture gallery')),
              subtitle: Text(tr(context, 'A neat grid of your pictures near the bottom of the page')),
              onTap: () => Navigator.pop(context, const _PictureChoice(_Placement.gallery)),
            ),
            if (one)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(tr(context, 'Use as the logo')),
                subtitle: Text(tr(context, 'Shown in the top bar')),
                onTap: () => Navigator.pop(context, const _PictureChoice(_Placement.logo)),
              ),
            if (one && onPage.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(tr(context, 'Or replace a picture already on the page:'),
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              for (final img in onPage)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: Text(img.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () =>
                      Navigator.pop(context, _PictureChoice(_Placement.replace, img.index)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Style ───────────────────────────────────────────────────────────────────

/// Colour / font / size panel. Returns the new page HTML, or null.
Future<String?> showStyleSheet(BuildContext context, String html) async {
  final result = await showModalBottomSheet<QuickStyle>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _StyleSheet(initial: readQuickStyle(html)),
  );
  if (result == null) return null;
  return applyQuickStyle(html, result);
}

class _StyleSheet extends StatefulWidget {
  const _StyleSheet({required this.initial});
  final QuickStyle initial;

  @override
  State<_StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<_StyleSheet> {
  late String? _text = widget.initial.textColor;
  late String? _heading = widget.initial.headingColor;
  late String? _background = widget.initial.backgroundColor;
  late String? _accent = widget.initial.accentColor;
  late String? _bar = widget.initial.barColor;
  late String? _font = widget.initial.fontFamily;
  late double _scale = widget.initial.fontScale ?? 1.0;

  static const _swatches = [
    '#111827', '#374151', '#6b7280', '#ffffff', '#dc2626', '#ea580c',
    '#eab308', '#16a34a', '#0d9488', '#2563eb', '#1e3a8a', '#7c3aed',
    '#db2777', '#92400e', '#fef3c7', '#eff6ff',
  ];

  Color _c(String hex) {
    final h = hex.replaceFirst('#', '');
    final full = h.length == 3 ? h.split('').map((c) => '$c$c').join() : h;
    return Color(int.parse('ff$full', radix: 16));
  }

  Widget _colorRow(String label, String? value, ValueChanged<String?> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (value != null)
              TextButton(onPressed: () => onPick(null), child: Text(tr(context, 'Default'))),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hex in _swatches)
                Semantics(
                  button: true,
                  selected: value == hex,
                  label: hex,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onPick(hex),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _c(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: value == hex ? AppColors.primary : Colors.black26,
                          width: value == hex ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(tr(context, 'Style'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              tr(context, 'Tip: you can also type it, e.g. "make the text dark blue".'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            _colorRow(tr(context, 'Text colour'), _text, (v) => setState(() => _text = v)),
            _colorRow(tr(context, 'Headings'), _heading, (v) => setState(() => _heading = v)),
            _colorRow(tr(context, 'Background'), _background, (v) => setState(() => _background = v)),
            _colorRow(tr(context, 'Buttons & links'), _accent, (v) => setState(() => _accent = v)),
            _colorRow(tr(context, 'Top bar'), _bar, (v) => setState(() => _bar = v)),
            Text(tr(context, 'Font'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(tr(context, 'Default')),
                  selected: _font == null,
                  onSelected: (_) => setState(() => _font = null),
                ),
                for (final e in kQuickFonts.entries)
                  ChoiceChip(
                    label: Text(tr(context, e.value.label)),
                    selected: _font == e.key,
                    onSelected: (_) => setState(() => _font = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              trFill(context, 'Text size: {n}%', {'n': '${(_scale * 100).round()}'}),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Slider(
              value: _scale,
              min: 0.8,
              max: 1.5,
              divisions: 14,
              onChanged: (v) => setState(() => _scale = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, const QuickStyle()),
                  child: Text(tr(context, 'Reset all')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    QuickStyle(
                      textColor: _text,
                      headingColor: _heading,
                      backgroundColor: _background,
                      accentColor: _accent,
                      barColor: _bar,
                      fontFamily: _font,
                      fontScale: _scale == 1.0 ? null : double.parse(_scale.toStringAsFixed(2)),
                    ),
                  ),
                  child: Text(tr(context, 'Apply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// For builders' "change this" bar: applies a style request instantly when
/// it is one ("make the text red"), returning the new HTML; null means "not
/// a style request — ask the coder model".
String? tryQuickStyleInstruction(String html, String instruction) {
  final current = readQuickStyle(html);
  final change = parseQuickStyleRequest(instruction, current: current);
  if (change == null) return null;
  return applyQuickStyle(html, current.merge(change));
}
