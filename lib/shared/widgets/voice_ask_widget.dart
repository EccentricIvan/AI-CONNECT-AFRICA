import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';

class VoiceAskWidget extends StatefulWidget {
  const VoiceAskWidget({super.key, this.onSubmit});

  final ValueChanged<String>? onSubmit;

  @override
  State<VoiceAskWidget> createState() => _VoiceAskWidgetState();
}

class _VoiceAskWidgetState extends State<VoiceAskWidget> {
  final _controller = TextEditingController();

  static const _prompts = [
    'Explain photosynthesis',
    'Teach me Python',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.search, color: Theme.of(context).hintColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: tr(context, 'Ask AI anything...'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    fillColor: Colors.transparent,
                    filled: false,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                // Same logo gradient as the Home composer's send button.
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.fabGradient,
                  ),
                  child: IconButton(
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                    ),
                    tooltip: 'Send',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _prompts
              .map(
                (p) => ActionChip(
                  label: Text(
                    p,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  onPressed: () => setState(() => _controller.text = p),
                  backgroundColor: cs.surface,
                  side: BorderSide(color: Theme.of(context).dividerColor),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
