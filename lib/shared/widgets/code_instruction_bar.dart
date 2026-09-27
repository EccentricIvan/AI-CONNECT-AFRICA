import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';
import '../coding/html_images.dart' show PickedImage;

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
        action: SnackBarAction(label: tr(context, 'Undo'), onPressed: onUndo),
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
    this.onPickImages,
    this.onSubmitWithImages,
  });

  final bool busy;
  final ValueChanged<String> onSubmit;

  /// When set (with [onSubmitWithImages]), the bar gets a picture button:
  /// the learner attaches pictures and says what to do with them.
  final Future<List<PickedImage>> Function()? onPickImages;
  final void Function(String instruction, List<PickedImage> images)?
  onSubmitWithImages;

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
  List<PickedImage> _images = const [];

  bool get _canAttach =>
      widget.onPickImages != null && widget.onSubmitWithImages != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.busy) return;
    final text = _controller.text.trim();
    if (_images.isNotEmpty && _canAttach) {
      widget.onSubmitWithImages!(text, _images);
      setState(() => _images = const []);
      _controller.clear();
      return;
    }
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  Future<void> _attach() async {
    final picked = await widget.onPickImages!();
    if (picked.isEmpty || !mounted) return;
    setState(() => _images = [..._images, ...picked]);
  }

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (_canAttach) ...[
          IconButton(
            tooltip: tr(context, 'Add a picture and say what to do with it'),
            onPressed: widget.busy ? null : _attach,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: !widget.busy,
            onSubmitted: (_) => _send(),
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              isDense: true,
              hintText: _images.isNotEmpty
                  ? tr(
                      context,
                      'Say what to do with the picture — e.g. make it the logo',
                    )
                  : tr(context, widget.hintText ?? 'Tell AI what to change'),
              prefixIcon: Icon(widget.icon, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
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
    if (_images.isEmpty) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _images.length; i++)
                InputChip(
                  avatar: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      _images[i].bytes,
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_outlined, size: 18),
                    ),
                  ),
                  label: Text(_images[i].name, overflow: TextOverflow.ellipsis),
                  onDeleted: widget.busy
                      ? null
                      : () =>
                            setState(() => _images = [..._images]..removeAt(i)),
                ),
            ],
          ),
        ),
        row,
      ],
    );
  }
}
