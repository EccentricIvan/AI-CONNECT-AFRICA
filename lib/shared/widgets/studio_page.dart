import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import 'app_shell.dart';

const kEduIllustrationAsset = 'assets/illustrations/home-secondary-learner.png';

/// Rounded educational thumbnail used in headers (no avatars).
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
      ),
    );
  }
}

/// Opens the app drawer from a screen that still uses a plain [AppBar].
///
/// The shell used to paint a floating menu button over every screen; that was
/// removed when [StudioAppBar] took over the chrome, which left the screens
/// that were never converted (the labs, the site/website builders, the
/// teacher detail view) with no way to reach the drawer at all. Their own
/// [Scaffold] has no drawer, so `AppBar` will not draw a hamburger for them.
class StudioDrawerButton extends StatelessWidget {
  const StudioDrawerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded),
      tooltip: tr(context, 'Menu'),
      onPressed: () => AppShell.mobileScaffoldKey.currentState?.openDrawer(),
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
      color: ac.iconWell,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22, color: ac.textPrimary),
              if (badge)
                Positioned(
                  top: 11,
                  right: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4D4F),
                      shape: BoxShape.circle,
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

/// Shared dashboard header: educational image + title + actions (no avatar).
class StudioPageHeader extends StatelessWidget {
  const StudioPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showMenu = true,
    this.showNotifications = false,
    this.showEduImage = true,
    this.showBack = false,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 12),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showMenu;
  final bool showNotifications;
  final bool showEduImage;
  final bool showBack;
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
            const SizedBox(width: 10),
          ] else if (showEduImage) ...[
            const EduImageBadge(),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ac.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
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
          if (showMenu) ...[
            const SizedBox(width: 8),
            StudioHeaderIconButton(
              icon: Icons.menu_rounded,
              tooltip: 'Menu',
              onTap: () =>
                  AppShell.mobileScaffoldKey.currentState?.openDrawer(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Drop-in AppBar replacement that matches the home dashboard chrome.
class StudioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudioAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showMenu = true,
    this.showNotifications = false,
    this.showEduImage = true,
    this.showBack = false,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showMenu;
  final bool showNotifications;
  final bool showEduImage;
  final bool showBack;
  final PreferredSizeWidget? bottom;

  double get _toolbarHeight => subtitle != null ? 76 : 68;

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
        actions: actions,
        showMenu: showMenu,
        showNotifications: showNotifications,
        showEduImage: showEduImage,
        showBack: showBack,
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      ),
      bottom: bottom,
    );
  }
}

/// Section title row matching home ("Learn" + "View all >").
class StudioSectionHeader extends StatelessWidget {
  const StudioSectionHeader({
    super.key,
    required this.title,
    this.actionLabel = 'View all >',
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
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Saira',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ac.textPrimary,
              ),
            ),
          ),
          if (onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft blue hero strip with educational illustration — reuse on hub screens.
class StudioHeroBanner extends StatelessWidget {
  const StudioHeroBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
    this.height = 148,
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
              ? const [Color(0xFF1A2E44), Color(0xFF152536)]
              : const [Color(0xFFE8F4FF), Color(0xFFF5FAFF)],
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
                      fontSize: 20,
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
                    TextButton(
                      onPressed: onCta,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        ctaLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 8,
            child: Image.asset(
              kEduIllustrationAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        ],
      ),
    );
  }
}
