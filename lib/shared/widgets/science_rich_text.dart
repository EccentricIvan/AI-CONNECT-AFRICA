import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../ai_core/science/science_text.dart';

/// Inline science renderer for streamed tutor / student text.
///
/// * Bare formulas (`H2O`, `CO2`, `x^2`) → Unicode sub/superscripts.
/// * `$H_2O$` / `$$...$$` → [Math.tex] (flutter_math_fork KaTeX, offline).
/// * Remaining prose → [MarkdownBody].
/// * Wide TeX blocks scroll horizontally instead of clipping the card.
class ScienceRichText extends StatelessWidget {
  const ScienceRichText({
    super.key,
    required this.text,
    this.style,
    this.color,
    this.shrinkWrap = true,
  });

  final String text;
  final TextStyle? style;
  final Color? color;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? DefaultTextStyle.of(context).style).copyWith(
      color: color ?? style?.color,
      height: style?.height ?? 1.6,
    );
    final spans = splitScienceSpans(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final span in spans)
          if (span.isMath)
            _TeXScroller(
              tex: span.text,
              display: span.displayMath,
              fallbackStyle: base,
            )
          else if (span.text.isNotEmpty)
            MarkdownBody(
              data: formatScienceProse(span.text),
              shrinkWrap: shrinkWrap,
              softLineBreak: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: base,
                strong: base.copyWith(fontWeight: FontWeight.w700),
                em: base.copyWith(fontStyle: FontStyle.italic),
                h1: base.copyWith(
                  fontSize: (base.fontSize ?? 14) * 1.35,
                  fontWeight: FontWeight.w700,
                ),
                h2: base.copyWith(
                  fontSize: (base.fontSize ?? 14) * 1.22,
                  fontWeight: FontWeight.w700,
                ),
                h3: base.copyWith(
                  fontSize: (base.fontSize ?? 14) * 1.1,
                  fontWeight: FontWeight.w700,
                ),
                listBullet: base,
                listIndent: 24,
                blockSpacing: 8,
                pPadding: const EdgeInsets.only(bottom: 6),
                h1Padding: const EdgeInsets.only(top: 4, bottom: 6),
                h2Padding: const EdgeInsets.only(top: 4, bottom: 4),
                h3Padding: const EdgeInsets.only(top: 2, bottom: 4),
                code: base.copyWith(
                  fontFamily: 'Consolas',
                  fontSize: (base.fontSize ?? 14) * 0.92,
                  backgroundColor: const Color(0xFF0F172A),
                  color: const Color(0xFFE2E8F0),
                ),
                codeblockPadding: const EdgeInsets.all(12),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
      ],
    );
  }
}

class _TeXScroller extends StatelessWidget {
  const _TeXScroller({
    required this.tex,
    required this.display,
    required this.fallbackStyle,
  });

  final String tex;
  final bool display;
  final TextStyle fallbackStyle;

  @override
  Widget build(BuildContext context) {
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: fallbackStyle.copyWith(
        fontSize: (fallbackStyle.fontSize ?? 14) * (display ? 1.15 : 1.0),
      ),
      onErrorFallback: (_) => Text(
        formatScienceProse(tex),
        style: fallbackStyle,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: display ? 8 : 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: math,
      ),
    );
  }
}
