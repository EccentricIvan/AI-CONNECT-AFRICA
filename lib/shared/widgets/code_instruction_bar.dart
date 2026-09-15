import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';

/// Result message for an applied instruction: what changed, an Undo, and an
/// X to dismiss it.
///
/// Without [SnackBar.showCloseIcon] the bar sits over the editor for its full
/// duration and the only way to clear it is to trigger the Undo you do not
/// want — so the student either waits or loses the change. The X is the way
/// out, and the long duration is only safe because of it.
void showInstructionAppliedSnack(
  BuildContext context, {
  required VoidCallback onUndo,
  String? message,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message ?? tr(context, 'Change applied.')),
        showCloseIcon: true,
        closeIconColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: tr(context, 'Undo'),
          onPressed: onUndo,
        ),
      ),
    );
}

/// Same chrome, no Undo — for a message the student only needs to read.
void showInstructionNoticeSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        showCloseIcon: true,
        closeIconColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
}

/// Chat-style instruction bar for the code editor toolbar — the student
/// types a plain-English change ("center the text", "change color to blue")
/// and the coder model applies exactly that edit to the current code.
class CodeInstructionBar extends StatefulWidget {
  const CodeInstructionBar({
    super.key,
    required this.busy,
    required this.onSubmit,
    this.hintText,
    this.icon = Icons.auto_awesome,
    this.tooltip,
  });

  final bool busy;
  final ValueChanged<String> onSubmit;

  /// Defaults to "Tell AI what to change". Sections where the model explains
  /// rather than edits override it, so the bar never promises an edit it will
  /// not make.
  final String? hintText;

  final IconData icon;
  final String? tooltip;

  @override
  State<CodeInstructionBar> createState() => _CodeInstructionBarState();
}

class _CodeInstructionBarState extends State<CodeInstructionBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: !widget.busy,
            onSubmitted: (_) => _send(),
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              isDense: true,
              hintText: tr(context, widget.hintText ?? 'Tell AI what to change'),
              prefixIcon: Icon(widget.icon, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: tr(context, widget.tooltip ?? 'Apply change'),
          onPressed: widget.busy ? null : _send,
          icon: widget.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.arrow_upward),
        ),
      ],
    );
  }
}
