import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';

/// Persistent banner showing whether real AI or demo answers are active.
class AiStatusBanner extends ConsumerWidget {
  const AiStatusBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(aiStatusProvider);

    return statusAsync.when(
      loading: () => _BannerShell(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderColor: AppColors.primary.withValues(alpha: 0.2),
        icon: Icons.hourglass_top_rounded,
        iconColor: AppColors.primary,
        title: 'Starting AI…',
        detail: compact ? null : 'Getting the classroom assistant ready',
      ),
      error: (e, _) => _BannerShell(
        color: const Color(0xFFFFF1F0),
        borderColor: const Color(0xFFF5C2C0),
        icon: Icons.error_outline_rounded,
        iconColor: const Color(0xFFC62828),
        title: 'AI unavailable',
        detail: compact ? null : 'Open Settings to finish setup',
        actionLabel: 'Settings',
        onAction: () => context.push('/settings'),
      ),
      data: (status) {
        if (!status.isDemo) {
          if (compact) return const SizedBox.shrink();
          return _BannerShell(
            color: AppColors.teachColor.withValues(alpha: 0.08),
            borderColor: AppColors.teachColor.withValues(alpha: 0.25),
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.teachColor,
            title: status.title,
            detail: status.detail,
          );
        }
        return _BannerShell(
          color: const Color(0xFFFFF8E7),
          borderColor: const Color(0xFFE8D4A8),
          icon: Icons.info_outline_rounded,
          iconColor: const Color(0xFFB86E00),
          title: status.title,
          detail: compact ? null : status.detail,
          actionLabel: 'Settings',
          onAction: () => context.push('/settings'),
        );
      },
    );
  }
}

class _BannerShell extends StatelessWidget {
  const _BannerShell({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: detail == null ? title : '$title. $detail',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.of(context).textPrimary,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.of(context).textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
