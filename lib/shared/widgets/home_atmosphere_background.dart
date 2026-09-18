import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Home / shell canvas using the official reference atmosphere artwork.
///
/// Desktop uses the landscape plate; mobile uses the portrait plate so the
/// wave field fills the phone viewport without awkward cropping.
class HomeAtmosphereBackground extends StatelessWidget {
  const HomeAtmosphereBackground({super.key, required this.child});

  final Widget child;

  static const desktopAssetPath = 'assets/branding/home_atmosphere.jpg';
  static const mobileAssetPath = 'assets/branding/home_atmosphere_mobile.jpg';

  @override
  Widget build(BuildContext context) {
    final ac = AppColors.of(context);
    if (ac.isDark) {
      return ColoredBox(color: ac.bgBottom, child: child);
    }

    final narrow = MediaQuery.sizeOf(context).width < 640;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.white),
        Positioned.fill(
          child: Image.asset(
            narrow ? mobileAssetPath : desktopAssetPath,
            fit: BoxFit.cover,
            alignment: narrow ? Alignment.center : Alignment.bottomCenter,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
        child,
      ],
    );
  }
}

/// Hides desktop/mobile scrollbars for Home chrome that should feel fixed.
class NoScrollbarBehavior extends MaterialScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
