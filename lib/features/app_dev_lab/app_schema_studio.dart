import 'package:flutter/material.dart';

import 'app_build_intent.dart';
import 'ui_schema_interpreter.dart';

/// Dual-tab App Dev Lab workspace: Preview Layout ↔ View Source Code.
class AppSchemaStudio extends StatefulWidget {
  const AppSchemaStudio({
    super.key,
    required this.controller,
    required this.intent,
    this.initialSource = '',
    this.onApply,
    this.toolbar,
    this.showApplyFab = true,
  });

  final TextEditingController controller;
  final AppBuildIntent intent;
  final String initialSource;
  final VoidCallback? onApply;
  final Widget? toolbar;
  final bool showApplyFab;

  @override
  State<AppSchemaStudio> createState() => _AppSchemaStudioState();
}

class _AppSchemaStudioState extends State<AppSchemaStudio> {
  late String _previewSource;
  var _epoch = 0;
  var _tab = 0; // 0 preview, 1 source

  @override
  void initState() {
    super.initState();
    _previewSource = widget.controller.text.isNotEmpty
        ? widget.controller.text
        : widget.initialSource;
    if (widget.controller.text.isEmpty && widget.initialSource.isNotEmpty) {
      widget.controller.text = widget.initialSource;
    }
    if (_previewSource.trim().isEmpty) {
      _previewSource = fallbackUiSchemaSource(widget.intent);
      widget.controller.text = _previewSource;
    }
  }

  @override
  void didUpdateWidget(covariant AppSchemaStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSource != oldWidget.initialSource &&
        widget.initialSource.isNotEmpty &&
        widget.controller.text != widget.initialSource) {
      widget.controller.text = widget.initialSource;
      _previewSource = widget.initialSource;
      _epoch++;
    }
  }

  void _applyNow() {
    var next = widget.controller.text.trim();
    if (next.isEmpty || parseUiSchema(next) == null) {
      next = fallbackUiSchemaSource(widget.intent);
      widget.controller.text = next;
    }
    setState(() {
      _previewSource = next;
      _epoch++;
      _tab = 0;
    });
    widget.onApply?.call();
  }

  @override
  Widget build(BuildContext context) {
    final previewPane = Column(
      children: [
        _header(
          icon: Icons.preview_outlined,
          title: 'Preview Layout',
          trailing: const Text(
            'Native Flutter · schema',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: UiSchemaInterpreter(
              key: ValueKey('schema-$_epoch'),
              source: _previewSource,
              intent: widget.intent,
            ),
          ),
        ),
      ],
    );

    final sourcePane = Column(
      children: [
        _header(
          icon: Icons.code,
          title: 'View Source Code',
          trailing: TextButton.icon(
            onPressed: _applyNow,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Apply Changes'),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              controller: widget.controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                hintText:
                    'OTIC_UI_V1 schema — Type: Button, Action: Alert, Style: Cyberpunk',
              ),
            ),
          ),
        ),
        if (widget.toolbar != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: widget.toolbar!,
          ),
      ],
    );

    return Stack(
      children: [
        Column(
          children: [
            Material(
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _tab = 0),
                      icon: Icon(
                        Icons.preview_outlined,
                        size: 18,
                        color: _tab == 0
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFF64748B),
                      ),
                      label: Text(
                        'Preview Layout',
                        style: TextStyle(
                          fontWeight:
                              _tab == 0 ? FontWeight.w700 : FontWeight.w500,
                          color: _tab == 0
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _tab = 1),
                      icon: Icon(
                        Icons.code,
                        size: 18,
                        color: _tab == 1
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFF64748B),
                      ),
                      label: Text(
                        'View Source Code',
                        style: TextStyle(
                          fontWeight:
                              _tab == 1 ? FontWeight.w700 : FontWeight.w500,
                          color: _tab == 1
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [previewPane, sourcePane],
              ),
            ),
          ],
        ),
        if (widget.showApplyFab)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _applyNow,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Apply Changes'),
            ),
          ),
      ],
    );
  }

  Widget _header({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
