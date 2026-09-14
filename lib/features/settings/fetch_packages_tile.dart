import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../screens/package_fetch_screen.dart';
import '../../services/model_fetch_service.dart';

/// Compact Settings entry for classroom package status / Install Packages.
///
/// Tap **Install Packages** to pull from Hugging Face into the same canonical
/// paths Windows and Android discovery already use. Filenames, sizes, and
/// paths are never shown.
class FetchPackagesTile extends ConsumerWidget {
  const FetchPackagesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelFetchControllerProvider);
    final controller = ref.read(modelFetchControllerProvider.notifier);
    final ready = state.isReady;
    final pct = (state.fraction * 100).clamp(0, 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(
            ready ? Icons.verified_outlined : Icons.inventory_2_outlined,
            color: ready ? AppColors.teachColor : AppColors.primary,
          ),
          title: const Text('System Core Configuration'),
          subtitle: Text(
            ready
                ? tr(context, 'All packages installed.')
                : 'Workspace Optimization — tap Install Packages once on this '
                    'device (Windows or Android), then learn fully offline.',
          ),
          isThreeLine: !ready,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.isFetching) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.statusLabel.isEmpty
                            ? 'Initializing offline classroom systems...'
                            : state.statusLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: state.totalBytes > 0 ? state.fraction : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
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
                FilledButton(
                  onPressed: () async {
                    await controller.fetchCore();
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    state.phase == ModelFetchPhase.failed
                        ? tr(context, 'Resume')
                        : 'Install Packages',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PackageFetchScreen(
                          embedded: false,
                          skipToHomeWhenCached: false,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open installer'),
                ),
              ],
              if (state.phase == ModelFetchPhase.failed) ...[
                const SizedBox(height: 8),
                Text(
                  'Setup could not complete. Please try again.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
