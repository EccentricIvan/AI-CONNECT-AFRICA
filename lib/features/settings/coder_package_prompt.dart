import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../services/model_fetch_service.dart';

/// Ensures the on-demand coding package is present before a studio build.
///
/// Returns `true` when ready (already on disk or just fetched).
/// Returns `false` if dismissed or fetch failed.
/// Never re-downloads when the file already exists on this device.
Future<bool> promptAndFetchCoderPackage(
  BuildContext context,
  WidgetRef ref,
) async {
  final svc = ref.read(modelFetchServiceProvider);
  if (await svc.isCoderReady()) return true;
  if (!context.mounted) return false;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'Studio package needed')),
      content: Text(
        tr(
          ctx,
          'This workspace needs an extra offline package the first time you '
          'use it. Download once — it stays on this device afterwards.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(ctx, 'Not now')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ctx, 'Fetch package')),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;

  final controller = ref.read(modelFetchControllerProvider.notifier);
  final fetchFuture = controller.fetchCoder();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(modelFetchControllerProvider);
          if (!state.isFetching &&
              (state.coderReady || state.phase == ModelFetchPhase.failed)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            });
          }
          return AlertDialog(
            title: Text(tr(ctx, 'Setting up studio')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: state.totalBytes > 0 ? state.fraction : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                Text(
                  state.statusLabel.isEmpty
                      ? 'Initializing offline classroom systems...'
                      : state.statusLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              if (state.isFetching)
                TextButton(
                  onPressed: () {
                    controller.cancel();
                    Navigator.pop(ctx);
                  },
                  child: Text(tr(ctx, 'Cancel')),
                ),
            ],
          );
        },
      );
    },
  );

  await fetchFuture;
  return svc.isCoderReady();
}
