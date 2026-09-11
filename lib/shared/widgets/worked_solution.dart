import 'package:flutter/material.dart';

import '../../ai_core/tutor/school_math.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import 'science_rich_text.dart';

/// MathGPT-style named steps with formulas in their own block.
class WorkedSolutionView extends StatelessWidget {
  const WorkedSolutionView({
    super.key,
    required this.solution,
    this.compact = false,
  });

  final SchoolMathSolution solution;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = solution.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 8 : 12),
          _StepCard(index: i + 1, step: steps[i], compact: compact),
        ],
        SizedBox(height: compact ? 10 : 14),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
          ),
          child: Text(
            '${tr(context, 'Answer')}: ${solution.answer}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 14 : 15,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.step,
    required this.compact,
  });

  final int index;
  final MathStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 22 : 24,
              height: compact ? 22 : 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$index',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  step.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : 14,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(left: compact ? 30 : 32, top: 4),
          child: Text(
            step.why,
            style: TextStyle(
              fontSize: compact ? 12.5 : 13.5,
              height: 1.45,
              color: cs.onSurface,
            ),
          ),
        ),
        if (step.formula != null && step.formula!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: compact ? 30 : 32, top: 6),
            child: _FormulaBox(text: step.formula!),
          ),
        if (step.calc != null && step.calc!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: compact ? 30 : 32, top: 6),
            child: _FormulaBox(text: step.calc!, emphasize: true),
          ),
      ],
    );
  }
}

class _FormulaBox extends StatelessWidget {
  const _FormulaBox({required this.text, this.emphasize = false});

  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: emphasize
            ? AppColors.createColor.withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ScienceRichText(
          text: text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13.5,
            height: 1.4,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
