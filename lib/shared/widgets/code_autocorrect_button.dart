import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';

/// Compact Autocorrect control for manual code editors.
class CodeAutocorrectButton extends StatelessWidget {
  const CodeAutocorrectButton({
    super.key,
    required this.busy,
    required this.onPressed,
    this.compact = false,
  });

  final bool busy;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: tr(context, 'Autocorrect code'),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_fix_high),
      );
    }
    return TextButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_fix_high, size: 18),
      label: Text(busy ? tr(context, 'Fixing…') : tr(context, 'Autocorrect')),
    );
  }
}
