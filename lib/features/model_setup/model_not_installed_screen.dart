import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ai_core/model/model_manager.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../settings/fetch_packages_tile.dart';

class ModelNotInstalledScreen extends ConsumerStatefulWidget {
  const ModelNotInstalledScreen({
    super.key,
    required this.info,
    this.onTryDemo,
    this.bootstrapError,
  });

  final ModelInfo info;

  /// Called when the student picks "Try demo mode" instead of installing —
  /// lets the caller (ModelGate) reveal the real chat screen, which already
  /// falls back to canned demo answers when no model is loaded. Falls back
  /// to popping the route if not provided.
  final VoidCallback? onTryDemo;

  /// Set when a fat APK tried to stream bundled models out of assets and
  /// failed (e.g. not enough free storage).
  final String? bootstrapError;

  @override
  ConsumerState<ModelNotInstalledScreen> createState() =>
      _ModelNotInstalledScreenState();
}

class _ModelNotInstalledScreenState
    extends ConsumerState<ModelNotInstalledScreen> {
  bool _installing = false;
  double _progress = 0;
  String? _error;

  Future<void> _pickAndInstall() async {
    setState(() => _error = null);

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select the Qwen tutor model (.litertlm)',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return; // user cancelled

    setState(() {
      _installing = true;
      _progress = 0;
    });

    try {
      final manager = ref.read(modelManagerProvider);
      final info = await manager.installFromFile(
        path,
        onProgress: (p) {
          // Throttle rebuilds — a 1 GB copy emits thousands of chunks.
          if (p - _progress >= 0.01 || p >= 1) {
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted) return;
      if (info.isReady) {
        ref.invalidate(modelInfoProvider);
      } else {
        setState(() {
          _installing = false;
          _error =
              'The file was copied but failed verification. '
              'Please try a fresh copy of the model file.';
        });
      }
    } on ModelInstallException catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = 'Install failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.memory_outlined,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'AI Model Not Installed',
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.info.status == ModelStatus.corrupted
                        ? 'A model file was found but appears corrupted or '
                              'incomplete. Please reinstall it below.'
                        : 'Download the tutor and translation models once '
                              '(internet required for that step). They are saved '
                              'on this device, then chat works offline in your '
                              'learning language. You can also copy the files '
                              'from a USB drive.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.bootstrapError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'Could not unpack the bundled model: '
                        '${widget.bootstrapError}\n\n'
                        'Free about 1 GB of storage, or install from a file below.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const FetchPackagesTile(),
                  const SizedBox(height: 8),
                  if (_installing) ...[
                    _InstallProgress(progress: _progress),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Install from file…'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _pickAndInstall,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _InstructionsCard(ref: ref),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Check again'),
                            onPressed: () => ref.invalidate(modelInfoProvider),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.science_outlined),
                            label: const Text('Try demo mode'),
                            onPressed:
                                widget.onTryDemo ?? () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallProgress extends StatelessWidget {
  const _InstallProgress({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Installing model… ${(progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 12),
          Text(
            'Copying the model into the app — this can take a few minutes. '
            'Keep the app open.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InstructionsCard extends ConsumerWidget {
  const _InstructionsCard({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(modelManagerProvider);
    return FutureBuilder<String>(
      future: manager.installInstructions(),
      builder: (context, snap) {
        final text = snap.data ?? 'Loading instructions...';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.usb, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Install by hand instead',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy path',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: text)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
