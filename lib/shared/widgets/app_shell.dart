import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_info_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../features/learn/path/path_provider.dart';
import '../../l10n/app_locale.dart';

const _brandLogoAsset = 'assets/branding/ai-connect-africa-logo.png';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static final mobileScaffoldKey = GlobalKey<ScaffoldState>();

  static const _destinations = [
    _NavDest('Home', Icons.home_outlined, Icons.home_rounded, '/'),
    _NavDest('Learn', Icons.menu_book_outlined, Icons.menu_book_rounded, '/learn'),
    _NavDest('Practice', Icons.edit_outlined, Icons.edit_rounded, '/practice'),
    _NavDest('Create', Icons.lightbulb_outlined, Icons.lightbulb_rounded, '/create'),
    _NavDest('Projects', Icons.folder_outlined, Icons.folder_rounded, '/projects'),
    _NavDest('AI Chat', Icons.chat_bubble_outline_rounded, Icons.chat_rounded, '/chat'),
    _NavDest('Teach back', Icons.school_outlined, Icons.school_rounded, '/teach'),
    _NavDest('Nearby', Icons.wifi_tethering_outlined, Icons.wifi_tethering_rounded, '/collaborate'),
    _NavDest(
      'Achievements',
      Icons.emoji_events_outlined,
      Icons.emoji_events_rounded,
      '/achievements',
    ),
    _NavDest(
      'Certificates',
      Icons.workspace_premium_outlined,
      Icons.workspace_premium_rounded,
      '/certificates',
    ),
    _NavDest('Teacher', Icons.groups_outlined, Icons.groups_rounded, '/teacher'),
    _NavDest('Settings', Icons.settings_outlined, Icons.settings_rounded, '/settings'),
  ];

  /// Flat bar items (chat is the raised center FAB).
  static const _mobileIndices = [0, 1, 2, 3];
  static const _chatPath = '/chat';

  /// Height of the flat bar itself, and how far the chat FAB rises above it.
  static const _kNavBarHeight = 72.0;
  static const _kFabOverhang = 18.0;

  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final i = _destinations.indexWhere((d) => d.path == path);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);
    final isWide = MediaQuery.sizeOf(context).width >= 640;
    final ac = AppColors.of(context);

    if (isWide) {
      return Container(
        decoration: AppColors.pageDecoration(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(
            children: [
              _SideNav(selectedIndex: selectedIndex, destinations: _destinations),
              Container(width: 1, color: ac.border),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    final path = GoRouterState.of(context).uri.path;
    final isChatActive = path == _chatPath;
    final mobileSelected = _mobileIndices.contains(selectedIndex)
        ? _mobileIndices.indexOf(selectedIndex)
        : -1;

    return Container(
      decoration: AppColors.pageDecoration(context),
      child: Scaffold(
        key: mobileScaffoldKey,
        backgroundColor: Colors.transparent,
        body: child,
        drawer: _AppDrawer(
          selectedIndex: selectedIndex,
          destinations: _destinations,
        ),
        // The chat FAB overhangs the top of the bar. It has to stay *inside*
        // the bottomNavigationBar's own box: Flutter paints a child that
        // overflows its parent (Clip.none) but will not route pointer events
        // to it, so a negative `top` here makes the overhanging strip of the
        // button visible and dead to taps. Instead the box is
        // _kFabOverhang taller than the bar, and the bar is pinned to its
        // bottom — same look, whole button tappable.
        bottomNavigationBar: SizedBox(
          height: _kNavBarHeight + _kFabOverhang + MediaQuery.paddingOf(context).bottom,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: ac.surface,
                    border: Border(top: BorderSide(color: ac.border)),
                    boxShadow: ac.isDark
                        ? const []
                        : const [
                            BoxShadow(
                              color: AppColors.glassShadow,
                              blurRadius: 16,
                              offset: Offset(0, -4),
                            ),
                          ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: _kNavBarHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            for (var i = 0; i < _mobileIndices.length; i++) ...[
                              Expanded(
                                child: _FloatingNavItem(
                                  icon: _destinations[_mobileIndices[i]].icon,
                                  selectedIcon: _destinations[_mobileIndices[i]]
                                      .selectedIcon,
                                  label: tr(
                                    context,
                                    _destinations[_mobileIndices[i]].label,
                                  ),
                                  selected: mobileSelected == i,
                                  onTap: () => context
                                      .go(_destinations[_mobileIndices[i]].path),
                                ),
                              ),
                              if (i == 1) const SizedBox(width: 64),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: _ChatFabButton(
                    active: isChatActive,
                    ringColor: ac.isDark ? ac.surface : Colors.white,
                    onTap: () => context.go(_chatPath),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingNavItem extends StatelessWidget {
  const _FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.of(context).textHint;

    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? selectedIcon : icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 3,
            width: selected ? 18 : 0,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ChatFabButton extends StatelessWidget {
  const _ChatFabButton({
    required this.active,
    required this.ringColor,
    required this.onTap,
  });

  final bool active;
  final Color ringColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr(context, 'AI Chat'),
      selected: active,
      child: Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 58,
          height: 58,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ringColor,
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.fabGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentGlow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              active ? Icons.chat_rounded : Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.selectedIndex, required this.destinations});

  final int selectedIndex;
  final List<_NavDest> destinations;

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    return Container(
      width: 220,
      color: ac.surface,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const _BrandLogo(size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI Connect Africa',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ac.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: ac.border),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: destinations.length,
              itemBuilder: (context, i) {
                final dest = destinations[i];
                final selected = selectedIndex == i;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Material(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => context.go(dest.path),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 32,
                              color: selected ? AppColors.accent : Colors.transparent,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected ? dest.selectedIcon : dest.icon,
                                      color: selected
                                          ? AppColors.accent
                                          : ac.textHint,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        tr(context, dest.label),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: selected
                                              ? AppColors.accent
                                              : ac.textHint,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(height: 1, color: ac.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.online,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                // Read the real build version. This line has been hand-edited
                // to a stale number more than once (it shipped as v1.1 while
                // pubspec said 1.2.0), so it no longer hardcodes anything.
                Consumer(
                  builder: (context, ref, _) {
                    final version =
                        ref.watch(packageInfoProvider).valueOrNull?.version;
                    return Text(
                      version == null
                          ? tr(context, 'Offline')
                          : '${tr(context, 'Offline')} · v$version',
                      style: TextStyle(fontSize: 12, color: ac.textHint),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.selectedIndex, required this.destinations});

  final int selectedIndex;
  final List<_NavDest> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathsAsync = ref.watch(studentPathsProvider);
    final ac = AppColors.of(context);

    return Drawer(
      backgroundColor: ac.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  const _BrandLogo(size: 40),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Connect Africa',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ac.textPrimary,
                        ),
                      ),
                      Text(
                        tr(context, 'Learn, Create & Build'),
                        style: TextStyle(fontSize: 11, color: ac.textHint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ac.border,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  pathsAsync.when(
                    data: (rows) {
                      if (rows.isEmpty) return const SizedBox.shrink();
                      final paths = rows.map(parsedFromRow).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                            child: Text(
                              'MY PATHS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: ac.textHint,
                              ),
                            ),
                          ),
                          ...paths.take(5).map(
                                (p) => ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.route,
                                    size: 18,
                                    color: AppColors.learnColor,
                                  ),
                                  title: Text(
                                    p.topic,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: ac.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${p.completedLessons}/${p.totalLessons} lessons',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: ac.textHint,
                                    ),
                                  ),
                                  trailing: Text(
                                    '${(p.progressFraction * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.learnColor,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    context.push(
                                      '/path/${Uri.encodeComponent(p.topic)}',
                                    );
                                  },
                                ),
                              ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            color: ac.border,
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  ...List.generate(destinations.length, (i) {
                    final dest = destinations[i];
                    final selected = selectedIndex == i;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Material(
                          color: selected
                              ? AppColors.accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              context.go(dest.path);
                              Navigator.pop(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected ? dest.selectedIcon : dest.icon,
                                    color: selected
                                        ? AppColors.accent
                                        : ac.textHint,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      tr(context, dest.label),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected
                                            ? AppColors.accent
                                            : ac.textHint,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDest {
  const _NavDest(this.label, this.icon, this.selectedIcon, this.path);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _brandLogoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Logo',
    );
  }
}
