import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ai_core/providers/ai_provider.dart';
import '../core/theme/app_colors.dart';
import '../l10n/app_locale.dart';
import '../services/model_fetch_service.dart';

/// Premium white-label installer for classroom packages (Windows + Android).
///
/// Flow:
/// 1. If packages are already discoverable → skip to home / call [onInstalled].
/// 2. Otherwise show **Install Packages**.
/// 3. Tap starts the Hugging Face fetch into the canonical install directory
///    used by [ModelManager] / AfriSLM on both platforms.
///
/// Never shows filenames, byte sizes, or on-disk paths.
class PackageFetchScreen extends ConsumerStatefulWidget {
  const PackageFetchScreen({
    super.key,
    this.onInstalled,
    this.onContinueWithoutInstall,
    this.skipToHomeWhenCached = true,
    this.embedded = false,
  });

  /// Called after a successful install when [embedded] (e.g. ModelGate).
  final VoidCallback? onInstalled;

  /// Optional “continue exploring” escape hatch (demo / sample answers).
  final VoidCallback? onContinueWithoutInstall;

  /// When true (default), cached packages → `pushReplacement` `/home`.
  final bool skipToHomeWhenCached;

  /// When true, stay in-place after install (invalidate providers) instead
  /// of navigating to `/home`.
  final bool embedded;

  @override
  ConsumerState<PackageFetchScreen> createState() => _PackageFetchScreenState();
}

class _PackageFetchScreenState extends ConsumerState<PackageFetchScreen> {
  bool _checking = true;
  bool _ownsFetch = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    // Only cancel if this screen started the download — Settings may own it.
    if (_ownsFetch) {
      ref.read(modelFetchControllerProvider.notifier).cancel();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final svc = ref.read(modelFetchServiceProvider);
    try {
      final cached = await svc.checkPackagesCached();
      if (!mounted) return;
      if (cached) {
        await ref.read(modelFetchControllerProvider.notifier).refresh();
        if (!mounted) return;
        if (widget.skipToHomeWhenCached && !widget.embedded) {
          _goHome();
          return;
        }
        if (widget.embedded) {
          widget.onInstalled?.call();
          return;
        }
      }
      setState(() => _checking = false);
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _goHome() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      context.go('/home');
      return;
    }
    Navigator.of(context).pushReplacementNamed('/home');
  }

  Future<void> _installPackages() async {
    final controller = ref.read(modelFetchControllerProvider.notifier);
    if (ref.read(modelFetchControllerProvider).isFetching) return;
    _ownsFetch = true;
    await controller.fetchCore();
    if (!mounted) return;
    _ownsFetch = false;

    final state = ref.read(modelFetchControllerProvider);
    if (!state.isReady) return;

    // Controllers already invalidate providers; give the gate a beat to reload.
    ref.invalidate(classroomPackagesReadyProvider);
    ref.invalidate(modelInfoProvider);
    ref.invalidate(translateModelInfoProvider);
    ref.invalidate(programmingModelInfoProvider);
    ref.invalidate(dualModelRuntimeProvider);
    ref.invalidate(engineLoadedProvider);

    if (widget.embedded) {
      widget.onInstalled?.call();
    } else {
      _goHome();
    }
  }

  void _cancel() {
    ref.read(modelFetchControllerProvider.notifier).cancel();
    _ownsFetch = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(modelFetchControllerProvider);

    if (_checking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 20),
              Text(
                'Checking workspace…',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pct = (state.fraction * 100).clamp(0, 100).round();
    final showProgress = state.isFetching;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              AppColors.primary.withValues(alpha: 0.04),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primary.withValues(alpha: 0.18),
                              AppColors.teachColor.withValues(alpha: 0.12),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'System Core Configuration',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Workspace Optimization',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tr(
                        context,
                        'Prepare this device for offline learning. '
                        'Tap Install Packages once to download tutor, '
                        'translation, and studio tools — then everything runs '
                        'on this device without the internet.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 36),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showProgress) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      state.statusLabel.isEmpty
                                          ? 'Initializing offline classroom systems...'
                                          : state.statusLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '$pct%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: AppColors.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: state.totalBytes > 0
                                      ? state.fraction
                                      : null,
                                  minHeight: 10,
                                  backgroundColor: AppColors.primary
                                      .withValues(alpha: 0.12),
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _cancel,
                                  child: Text(tr(context, 'Cancel')),
                                ),
                              ),
                            ] else if (state.isReady) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_rounded,
                                    color: AppColors.teachColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      tr(context, 'All packages installed.'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: widget.embedded
                                    ? widget.onInstalled
                                    : _goHome,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Continue'),
                              ),
                            ] else ...[
                              FilledButton(
                                onPressed: _installPackages,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                child: Text(
                                  state.phase == ModelFetchPhase.failed
                                      ? tr(context, 'Resume')
                                      : 'Install Packages',
                                ),
                              ),
                              if (state.phase == ModelFetchPhase.failed &&
                                  state.error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _sanitizeError(state.error!),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.error,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (widget.onContinueWithoutInstall != null &&
                        !showProgress) ...[
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: widget.onContinueWithoutInstall,
                        child: Text(tr(context, 'Try demo mode')),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'Packages download once from the classroom catalog, '
                      'then stay on this device. Nothing is shared to the cloud.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Drop path/filename leaks that downloader exceptions sometimes carry.
  static String _sanitizeError(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'[A-Za-z]:\\[^\s]+'), 'this device');
    s = s.replaceAll(RegExp(r'/[^\s]+'), 'this device');
    s = s.replaceAll(
      RegExp(
        r'[\w.-]+\.(gguf|litertlm|literlm|onnx|tflite)',
        caseSensitive: false,
      ),
      'package',
    );
    s = s.replaceAll(
      RegExp(r'\d+(\.\d+)?\s*(MB|GB|KB|bytes)', caseSensitive: false),
      '',
    );
    return s.trim().isEmpty
        ? 'Setup could not complete. Please try again.'
        : s.trim();
  }
}
