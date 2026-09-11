import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';

/// Chrome string that follows the session language tables.
class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.english, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String english;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      tr(context, english),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
