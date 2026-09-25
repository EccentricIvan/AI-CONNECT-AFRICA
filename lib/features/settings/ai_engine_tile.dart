import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show PreferredBackend;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/inference/litert_lm_engine.dart';
import '../../ai_core/model/device_tier.dart';
import '../../ai_core/model/model_runtime_policy.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';

/// Settings → Performance (phones only).
///
/// Standard mode is what the app picks for this phone. Faster mode lets the
/// assistant use the phone's graphics chip when it can; if that fails or
/// the app closes, the next start goes back to standard by itself (see
/// LiteRtLmEngineImpl). No engine or model names are shown to students.
class AiEngineTile extends ConsumerStatefulWidget {
  const AiEngineTile({super.key});

  @override
  ConsumerState<AiEngineTile> createState() => _AiEngineTileState();
}

class _AiEngineTileState extends ConsumerState<AiEngineTile> {
  bool _busy = false;

  Future<void> _set({required bool faster}) async {
    setState(() => _busy = true);
    if (faster) {
      await LiteRtLmEngineImpl.clearRememberedBackends(forceAcceleration: true);
    } else {
      await LiteRtLmEngineImpl.useTierDefault();
    }
    ref.invalidate(dualModelRuntimeProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(faster
          ? tr(context, 'Trying faster mode. If the app closes, reopen it — it goes back to standard mode.')
          : tr(context, 'Back to standard mode.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!androidUsesLiteRt) return const SizedBox.shrink();
    final rt = ref.watch(dualModelRuntimeProvider).valueOrNull;
    final brain = rt?.reasoner;
    final accelerated = brain is LiteRtLmEngineImpl &&
        (brain.activeBackend == PreferredBackend.gpu ||
            brain.activeBackend == PreferredBackend.npu);
    final ac = AppColors.of(context);

    return ListTile(
      leading: const Icon(Icons.speed_rounded, color: AppColors.primary),
      title: Text(tr(context, 'Performance')),
      subtitle: Text(
        accelerated
            ? tr(context, "Faster mode — using the phone's graphics chip.")
            : DeviceTier.current.isLowMemory
                ? tr(context, 'Standard mode — the most reliable setting for this phone.')
                : tr(context, 'Standard mode.'),
        style: TextStyle(color: ac.textSecondary),
      ),
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: () => _set(faster: !accelerated),
              child: Text(accelerated
                  ? tr(context, 'Use standard')
                  : tr(context, 'Try faster mode')),
            ),
    );
  }
}
