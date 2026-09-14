import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../services/model_fetch_service.dart';

/// White-label "Fetch packages" — tutor + translation only (never the coder).
///
/// Shows a single combined progress bar and anonymous status lines. Filenames,
/// GGUF/LiteRT/Qwen/AfriSLM branding are never shown. If both packages already
/// exist on disk, the tile stays Ready with zero network.
class FetchPackagesTile extends ConsumerWidget {
  const FetchPackagesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelFetchControllerProvider);
    final controller = ref.read(modelFetchControllerProvider.notifier);
    final ready = state.isReady;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(
            ready ? Icons.verified_outlined : Icons.cloud_download_outlined,
            color: ready ? AppColors.teachColor : AppColors.primary,
          ),
          title: Text(tr(context, 'Fetch packages')),
          subtitle: Text(
            ready
                ? tr(context, 'All packages installed.')
                : tr(
                    context,
                    'Download the AI models to this device. Needs internet '
                    'once — the app runs offline afterwards.',
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.isFetching) ...[
                LinearProgressIndicator(
                  value: state.totalBytes > 0 ? state.fraction : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                Text(
                  state.statusLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: controller.cancel,
                    child: Text(tr(context, 'Cancel')),
                  ),
                ),
              ] else if (ready) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      tr(context, 'Ready'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: controller.fetchCore,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    state.phase == ModelFetchPhase.failed
                        ? tr(context, 'Resume')
                        : tr(context, 'Fetch packages'),
                  ),
                ),
              ],
              if (state.phase == ModelFetchPhase.failed &&
                  state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
