import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/inference/runtime_config.dart';
import '../../ai_core/inference/sanitize_llm_response.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../l10n/language_provider.dart';
import '../../ai_core/tutor/school_math.dart';
import '../../ai_core/tutor/school_math_l10n.dart';
import '../../ai_core/tutor/tutor_contract.dart';
import '../../core/theme/app_colors.dart';
import '../../curriculum/curriculum_models.dart';
import '../../l10n/app_locale.dart';
import 'worked_solution.dart';

/// Button on a quiz question that streams a worked solution (steps + calculations).
class QuizAiAnswer extends ConsumerStatefulWidget {
  const QuizAiAnswer({super.key, required this.question});

  final QuizQuestion question;

  @override
  ConsumerState<QuizAiAnswer> createState() => _QuizAiAnswerState();
}

class _QuizAiAnswerState extends ConsumerState<QuizAiAnswer> {
  bool _busy = false;
  String _text = '';
  String? _error;
  SchoolMathSolution? _math;

  String _prompt() {
    final q = widget.question;
    final letter = String.fromCharCode(65 + q.correct.clamp(0, 25));
    final options = q.options.asMap().entries
        .map((e) => '${String.fromCharCode(65 + e.key)}) ${e.value}')
        .join('\n');
    return '''$kTutorContract
CURRICULUM: this quiz item. Teach the method. Correct option is $letter.
Q: ${q.question}
$options
Student: Explain with named steps (never Sum:). Show only necessary calculations.
Tutor:''';
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _text = '';
      _error = null;
      _math = null;
    });
    try {
      final q = widget.question;
      final solved = solveSchoolMath(
        '${q.question} ${q.options.join(' ')}',
      );
      if (solved != null) {
        final lang = ref.read(appLanguageProvider);
        var shown = solved;
        if (lang != 'en') {
          final pipeline = await ref.read(translationPipelineProvider.future);
          if (pipeline != null) {
            shown = await localizeSchoolMath(
              solved,
              translate: (english) => pipeline.fromEnglish(english, lang),
            );
          }
        }
        if (mounted) setState(() => _math = shown);
        return;
      }
      final engine = await ref.read(engineLoadedProvider.future);
      final raw = await engine.generate(
        prompt: _prompt(),
        maxTokens: kMaxNewTokens,
        temperature: kTutorTemperature,
        onToken: (token) {
          if (!mounted) return;
          setState(() => _text = sanitizeLLMResponse(_text + token));
        },
      );
      final shown = sanitizeLLMResponse(
        _text.trim().isNotEmpty ? _text : raw,
      );
      if (mounted) setState(() => _text = shown);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not get a worked solution. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(tr(context, 'Use AI to answer this question')),
        ),
        if (_math != null || _text.isNotEmpty || _error != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: _error != null
                ? Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.red,
                    ),
                  )
                : _math != null
                    ? WorkedSolutionView(solution: _math!, compact: true)
                    : Text(
                        _text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: cs.onSurface,
                        ),
                      ),
          ),
        ],
      ],
    );
  }
}
