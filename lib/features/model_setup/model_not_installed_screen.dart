import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_core/model/model_manager.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../screens/package_fetch_screen.dart';
import '../../services/model_fetch_service.dart';

/// Gate screen when classroom packages are missing.
///
/// Delegates entirely to the white-label [PackageFetchScreen] — no filenames,
/// sizes, or storage paths.
class ModelNotInstalledScreen extends ConsumerWidget {
  const ModelNotInstalledScreen({
    super.key,
    required this.info,
    this.onTryDemo,
    this.bootstrapError,
  });

  final ModelInfo info;
  final VoidCallback? onTryDemo;

  /// Kept for call-site compatibility; never shown as raw storage jargon.
  final String? bootstrapError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PackageFetchScreen(
      embedded: true,
      skipToHomeWhenCached: false,
      onInstalled: () {
        ref.invalidate(classroomPackagesReadyProvider);
        ref.invalidate(modelInfoProvider);
        ref.invalidate(translateModelInfoProvider);
        ref.invalidate(programmingModelInfoProvider);
        ref.invalidate(dualModelRuntimeProvider);
        ref.invalidate(engineLoadedProvider);
      },
      onContinueWithoutInstall: onTryDemo,
    );
  }
}
