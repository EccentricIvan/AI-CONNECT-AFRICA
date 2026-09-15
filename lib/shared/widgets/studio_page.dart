import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

const kEduIllustrationAsset = 'assets/illustrations/home-secondary-learner.png';

/// Gradient icon tile used as the leading mark on headers and cards.
class StudioIconChip extends StatelessWidget {
  const StudioIconChip({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 44,
    this.radius = 15,
    this.glow = true,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.28)!,
            color,
          ],
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}

/// Rounded educational thumbnail — kept for hero art, not used as an avatar.
class EduImageBadge extends StatelessWidget {
  const EduImageBadge({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        kEduIllustrationAsset,
        fit: BoxFit.cover,
        semanticLabel: 'Learning illustration',
        // A 1.5 MB source painted at 52 px. Without a decode hint the full
        // bitmap sits in memory, which matters on the 4 GB Android floor.
        cacheWidth: (size * 3).round(),
      ),
    );
  }
}

/// The app logo, for the one header that stands in for the app itself.
///
/// The redesign replaced home's logo-and-wordmark lockup with a generic
/// illustration, which dropped the branding `fc54a44` had deliberately added.
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/ai-connect-africa-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'AI Connect Africa',
    );
  }
}

class StudioHeaderIconButton extends StatelessWidget {
  const StudioHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final button = Material(
      color: ac.surface,
      shape: CircleBorder(side: BorderSide(color: ac.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 21, color: ac.textPrimary),
              if (badge)
                Positioned(
                  top: 10,
                  right: 11,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D4F),
                      shape: BoxShape.circle,
                      border: Border.all(color: ac.surface, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Shared page header: optional gradient icon mark, title, subtitle, actions.
class StudioPageHeader extends StatelessWidget {
  const StudioPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = AppColors.primary,
    this.actions = const [],
    @Deprecated('Hamburger menu removed from all screens') bool showMenu = false,
    this.showNotifications = false,
    this.showBack = false,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 12),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final List<Widget> actions;
  final bool showNotifications;
  final bool showBack;

  /// Replaces the default badge — home passes [BrandBadge] so the app still
  /// leads with its own logo rather than stock art.
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (showBack) ...[
            StudioHeaderIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            ),
            const SizedBox(width: 12),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ] else if (icon != null) ...[
            StudioIconChip(icon: icon!, color: iconColor, size: 42),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Saira',
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: ac.textPrimary,
                    height: 1.15,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: ac.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions.map(
            (w) => Padding(padding: const EdgeInsets.only(left: 8), child: w),
          ),
          if (showNotifications) ...[
            const SizedBox(width: 8),
            StudioHeaderIconButton(
              icon: Icons.notifications_none_rounded,
              badge: true,
              tooltip: 'Achievements',
              onTap: () => context.push('/achievements'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Drop-in AppBar replacement that matches the dashboard chrome.
class StudioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudioAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = AppColors.primary,
    this.actions = const [],
    @Deprecated('Hamburger menu removed from all screens') bool showMenu = false,
    this.showNotifications = false,
    this.showBack = false,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final List<Widget> actions;
  final bool showNotifications;
  final bool showBack;
  final PreferredSizeWidget? bottom;

  double get _toolbarHeight => subtitle != null ? 74 : 66;

  @override
  Size get preferredSize => Size.fromHeight(
        _toolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: _toolbarHeight,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: StudioPageHeader(
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        actions: actions,
        showNotifications: showNotifications,
        showBack: showBack,
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      ),
      bottom: bottom,
    );
  }
}

/// Section title with a gradient accent bar and a pill "view all" action.
class StudioSectionHeader extends StatelessWidget {
  const StudioSectionHeader({
    super.key,
    required this.title,
    this.actionLabel = 'View all',
    this.onAction,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.primaryLight, AppColors.accentDeep],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Saira',
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: ac.textPrimary,
              ),
            ),
          ),
          if (onAction != null)
            Material(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft gradient surface used for the app's content cards.
class StudioCard extends StatelessWidget {
  const StudioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    final tint = accent;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      child: Material(
        color: ac.surface,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: tint == null
                    ? ac.border
                    : tint.withValues(alpha: ac.isDark ? 0.30 : 0.18),
              ),
              gradient: tint == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tint.withValues(alpha: ac.isDark ? 0.16 : 0.10),
                        tint.withValues(alpha: ac.isDark ? 0.05 : 0.02),
                      ],
                    ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Slim gradient hero strip with educational illustration.
class StudioHeroBanner extends StatelessWidget {
  const StudioHeroBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
    this.height = 132,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ac.isDark
              ? const [Color(0xFF1A2750), Color(0xFF131E42)]
              : const [Color(0xFFEAF1FE), Color(0xFFF7F5FF)],
        ),
        border: Border.all(color: ac.border),
        boxShadow: ac.softShadow(ac.isDark),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.primary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Saira',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: ac.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: ac.textSecondary,
                      ),
                    ),
                  ),
                  if (ctaLabel != null && onCta != null)
                    Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        onTap: onCta,
                        borderRadius: BorderRadius.circular(99),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ctaLabel!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  kEduIllustrationAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        (ac.isDark
                                ? const Color(0xFF131E42)
                                : const Color(0xFFEAF1FE))
                            .withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
