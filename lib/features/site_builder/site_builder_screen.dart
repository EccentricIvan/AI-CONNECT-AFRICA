import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../features/website/site_assembler.dart';
import '../../features/website/site_blocks.dart';
import '../../shared/widgets/html_preview.dart';

/// Identity questions asked before building. Everything else on the page comes
/// from the vertical's preset copy, so a student can build a complete site
/// without filling anything in.
class _Ask {
  const _Ask(this.key, this.label, this.hint, {this.lines = 1});
  final String key, label, hint;
  final int lines;
}

const _asks = <_Ask>[
  _Ask('site_name', 'Name', 'e.g. Bright Future Academy'),
  _Ask('headline', 'Headline', 'The big line at the top of the page'),
  _Ask('subhead', 'Short description', 'One or two sentences', lines: 3),
  _Ask('email', 'Email', 'you@example.com'),
  _Ask('phone', 'Phone', '+256 700 123 456'),
  _Ask('address', 'Address', 'Town or street address'),
];

Color _hex(String s) =>
    Color(int.parse(s.replaceFirst('#', ''), radix: 16) | 0xFF000000);

class SiteBuilderScreen extends ConsumerStatefulWidget {
  const SiteBuilderScreen({super.key});

  @override
  ConsumerState<SiteBuilderScreen> createState() => _SiteBuilderScreenState();
}

class _SiteBuilderScreenState extends ConsumerState<SiteBuilderScreen> {
  final _assembler = SiteAssembler();
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _features = {};

  SiteVertical? _selected;
  String _previewHtml = '';
  bool _showPreview = false;
  bool _building = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectVertical(SiteVertical v) {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    for (final a in _asks) {
      _controllers[a.key] = TextEditingController();
    }

    _features
      ..clear()
      ..addAll(v.features.where((f) => f.on).map((f) => f.blockId));

    _previewHtml = '';
    setState(() {
      _selected = v;
      _showPreview = false;
    });
  }

  Future<void> _buildSite() async {
    final v = _selected;
    if (v == null || _building) return;
    setState(() => _building = true);
    try {
      final answers = <String, String>{
        for (final e in _controllers.entries) e.key: e.value.text,
      };
      final html = await _assembler.assemble(
        vertical: v,
        selected: _features,
        answers: answers,
      );
      if (!mounted) return;
      setState(() {
        _previewHtml = html;
        _showPreview = true;
      });
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  void _back() {
    setState(() {
      if (_showPreview) {
        _showPreview = false;
      } else {
        _selected = null;
      }
    });
  }

  void _openFullScreen() {
    if (_previewHtml.trim().isEmpty) return;
    showHtmlFullScreen(context, _previewHtml);
  }

  @override
  Widget build(BuildContext context) {
    final v = _selected;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.web, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(v == null
              ? 'Site Builder'
              : _showPreview
                  ? 'Preview'
                  : v.name),
        ]),
        leading: v != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
      ),
      floatingActionButton: v == null
          ? null
          : _showPreview
              ? FloatingActionButton.extended(
                  onPressed: _openFullScreen,
                  icon: const Icon(Icons.fullscreen),
                  label: const Text('Full Screen Preview'),
                )
              : FloatingActionButton.extended(
                  onPressed: _building ? null : _buildSite,
                  icon: _building
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.rocket_launch),
                  label: Text(_building ? 'BUILDING…' : 'BUILD'),
                  backgroundColor: _hex(v.brand),
                  foregroundColor: Colors.white,
                ),
      body: v == null
          ? _VerticalPicker(onSelect: _selectVertical)
          : _showPreview
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: BrowserFrame(html: _previewHtml),
                )
              : _Setup(
                  vertical: v,
                  controllers: _controllers,
                  features: _features,
                  onToggle: (id, on) => setState(
                      () => on ? _features.add(id) : _features.remove(id)),
                ),
    );
  }
}

// ── Vertical picker ──────────────────────────────────────────────────────────

class _VerticalPicker extends StatelessWidget {
  const _VerticalPicker({required this.onSelect});
  final void Function(SiteVertical) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose a Template',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface)),
          const SizedBox(height: 6),
          Text('Pick a design, choose your sections, and build a live website.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          ...kVerticals.map((v) {
            final color = _hex(v.brand);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: InkWell(
                onTap: () => onSelect(v),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [color, _hex(v.brand2)]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(v.emoji,
                            style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: scheme.onSurface)),
                            const SizedBox(height: 4),
                            Text(
                                '${v.features.length} optional sections · ready to build',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios,
                          size: 16, color: Theme.of(context).hintColor),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Setup: details + section toggles ─────────────────────────────────────────

class _Setup extends StatelessWidget {
  const _Setup({
    required this.vertical,
    required this.controllers,
    required this.features,
    required this.onToggle,
  });

  final SiteVertical vertical;
  final Map<String, TextEditingController> controllers;
  final Set<String> features;
  final void Function(String id, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hex(vertical.brand);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.auto_awesome, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Leave anything blank and we fill it in for you. '
                  'Choose your sections below, then tap BUILD.',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurface, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Text('Your details',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.onSurface)),
          const SizedBox(height: 12),
          ..._asks.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: controllers[a.key],
                  maxLines: a.lines,
                  decoration: InputDecoration(
                    labelText: a.label,
                    hintText: a.hint,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 10),
          Text('Sections',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('A header, hero, about and contact are always included.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ...vertical.features.map((f) => SwitchListTile.adaptive(
                value: features.contains(f.blockId),
                onChanged: (on) => onToggle(f.blockId, on),
                activeThumbColor: color,
                contentPadding: EdgeInsets.zero,
                title: Text(f.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                subtitle: Text(f.blurb,
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              )),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
