import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/inference/inference_engine.dart';
import '../../ai_core/inference/litert_lm_engine.dart';
import '../../ai_core/model/device_tier.dart';
import '../../ai_core/model/model_runtime_policy.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';

/// Settings → what actually runs: runtime and hardware per model, how long
/// it took to load, and a speed test — so "is the NPU/GPU really used?" has
/// an answer on the student's own phone.
class AiEngineTile extends ConsumerStatefulWidget {
  const AiEngineTile({super.key});

  @override
  ConsumerState<AiEngineTile> createState() => _AiEngineTileState();
}

class _AiEngineTileState extends ConsumerState<AiEngineTile> {
  bool _testing = false;
  String? _result;

  static String _runtime(InferenceEngine? e) {
    if (e == null) return 'not loaded';
    if (e.isDemo) return 'demo answers';
    if (e is LiteRtLmEngineImpl) {
      final load = e.loadTime == null ? '' : ' · loaded in ${(e.loadTime!.inMilliseconds / 1000).toStringAsFixed(1)} s';
      final speed = e.lastTokensPerSecond == null
          ? ''
          : ' · ${e.lastTokensPerSecond!.toStringAsFixed(1)} tok/s last answer';
      return 'LiteRT-LM · ${LiteRtLmEngineImpl.backendName(e.activeBackend)}$load$speed';
    }
    return 'llama.cpp · GGUF · CPU';
  }

  Future<void> _speedTest(InferenceEngine engine) async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final watch = Stopwatch()..start();
    var chunks = 0;
    Duration? first;
    try {
      await engine.generate(
        prompt: 'Explain in about fifty words why plants need sunlight.',
        maxTokens: 64,
        temperature: 0,
        onToken: (_) {
          first ??= watch.elapsed;
          chunks++;
        },
      );
      final secs = watch.elapsedMilliseconds / 1000;
      final decodeSecs = secs - (first?.inMilliseconds ?? 0) / 1000;
      setState(() => _result = trFill(
            context,
            'First words after {ttft} s · about {rate} tokens/s · {total} s total',
            {
              'ttft': ((first?.inMilliseconds ?? 0) / 1000).toStringAsFixed(1),
              'rate': decodeSecs > 0 ? (chunks / decodeSecs).toStringAsFixed(1) : '—',
              'total': secs.toStringAsFixed(1),
            },
          ));
    } catch (e) {
      setState(() => _result = 'Speed test failed: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _retryAcceleration() async {
    await LiteRtLmEngineImpl.clearRememberedBackends(forceAcceleration: true);
    ref.invalidate(dualModelRuntimeProvider);
    if (!mounted) return;
    setState(() => _result = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(context, 'Reloading the models — trying NPU and GPU. If the app closes, reopen it: it goes back to CPU.')),
    ));
  }

  Future<void> _useTierDefault() async {
    await LiteRtLmEngineImpl.useTierDefault();
    ref.invalidate(dualModelRuntimeProvider);
    if (!mounted) return;
    setState(() => _result = null);
  }

  @override
  Widget build(BuildContext context) {
    final runtimeAsync = ref.watch(dualModelRuntimeProvider);
    final ac = AppColors.of(context);
    return runtimeAsync.when(
      loading: () => ListTile(
        leading: const Icon(Icons.memory_rounded, color: AppColors.primary),
        title: Text(tr(context, 'AI engine')),
        subtitle: Text(tr(context, 'Loading the models…')),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.memory_rounded, color: Colors.orange),
        title: Text(tr(context, 'AI engine')),
        subtitle: Text('$e'),
      ),
      data: (rt) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.memory_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Text(tr(context, 'AI engine'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ]),
            const SizedBox(height: 8),
            Text(
              !androidUsesLiteRt
                  ? tr(context, 'This computer runs both models on llama.cpp (GGUF).')
                  : DeviceTier.current.isLowMemory
                      ? trFill(context,
                          '{tier}: both models run on the LiteRT-LM CPU backend with the smaller int4 translator — the fastest setup for phones with 4 GB. You can still try the GPU.',
                          {'tier': DeviceTier.current.label})
                      : trFill(context,
                          '{tier}: both models run on LiteRT-LM — NPU first, then GPU, then CPU.',
                          {'tier': DeviceTier.current.label}),
              style: TextStyle(fontSize: 12, color: ac.textSecondary),
            ),
            const SizedBox(height: 8),
            _row(context, tr(context, 'Tutor'), _runtime(rt.reasoner)),
            _row(context, tr(context, 'Translator'), _runtime(rt.translator)),
            if (_result != null) ...[
              const SizedBox(height: 6),
              Text(_result!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _testing || rt.reasoner.isDemo ? null : () => _speedTest(rt.reasoner),
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.speed_rounded, size: 18),
                label: Text(tr(context, 'Run speed test')),
              ),
              if (androidUsesLiteRt)
                OutlinedButton.icon(
                  onPressed: _retryAcceleration,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(DeviceTier.current.isLowMemory
                      ? tr(context, 'Try GPU anyway')
                      : tr(context, 'Retry NPU / GPU')),
                ),
              if (androidUsesLiteRt && DeviceTier.current.isLowMemory)
                TextButton(
                  onPressed: _useTierDefault,
                  child: Text(tr(context, 'Back to the recommended setting')),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}
