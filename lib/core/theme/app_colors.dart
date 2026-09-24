import 'package:flutter/material.dart';

/// AI Connect Africa brand tokens — white-first canvas, deep navy type, and
/// the logo's cyan→blue→violet gradient reserved for emphasis.
///
/// Every hue here is sampled from the app icon
/// (`assets/branding/ai-connect-africa-logo.png`): cyan #00A8EB at the top of
/// the ring, blue ~#0075E9 through the "AI", electric violet ~#5800E6 at the
/// bottom. Tokens used as text are nudged just dark enough to pass WCAG AA
/// on white; the raw logo values appear only inside gradients.
class AppColors {
  const AppColors._({
    required this.bgTop,
    required this.bgBottom,
    required this.pageGradientMid,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.border,
    required this.iconWell,
    required this.isDark,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color pageGradientMid;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color border;
  final Color iconWell;
  final bool isDark;

  Color get textOnSurface => textPrimary;
  Color get pageBg => bgBottom;
  Color get card => surface;

  static const AppColors light = AppColors._(
    bgTop: Color(0xFFF5F8FE),
    bgBottom: Color(0xFFF5F8FE),
    pageGradientMid: Color(0xFFF5F8FE),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0B1B4D),
    textSecondary: Color(0xFF46557A),
    textHint: Color(0xFF8290AE),
    border: Color(0xFFE2E9F7),
    iconWell: Color(0xFFEEF3FD),
    isDark: false,
  );

  static const AppColors darkTheme = AppColors._(
    bgTop: Color(0xFF070E22),
    bgBottom: Color(0xFF0A1330),
    pageGradientMid: Color(0xFF0A1330),
    surface: Color(0xFF131E42),
    textPrimary: Color(0xFFE8EEFC),
    textSecondary: Color(0xFFA3B2D6),
    textHint: Color(0xFF7385AD),
    border: Color(0xFF26345E),
    iconWell: Color(0xFF1A2750),
    isDark: true,
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTheme : light;

  static Color pageBackground(BuildContext context) =>
      of(context).isDark ? darkTheme.bgBottom : Colors.white;

  /// White-first shell canvas; HomeAtmosphereBackground adds bottom glow.
  static BoxDecoration pageDecoration(BuildContext context) {
    final c = of(context);
    if (c.isDark) {
      return BoxDecoration(color: c.bgBottom);
    }
    return const BoxDecoration(color: Colors.white);
  }

  // Brand
  static const Color primary = Color(0xFF1F6BE5);
  static const Color primaryLight = Color(0xFF5B9BF8);
  static const Color accent = Color(0xFF1F6BE5);
  static const Color accentDeep = Color(0xFF1449B8);
  static const Color secondary = brandViolet;

  /// The logo's gradient partners: cyan through blue to violet.
  static const Color brandCyan = Color(0xFF00A8EB);
  static const Color brandViolet = Color(0xFF5B1EE8);
  static const Color brandVioletDeep = Color(0xFF3F12B0);
  static const Color navy = Color(0xFF0B1B4D);

  static Color get accentGlow => primary.withValues(alpha: 0.24);

  static Color glassFill(BuildContext context, {bool strong = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (strong) {
      return dark
          ? const Color(0xFF1A2750).withValues(alpha: 0.95)
          : const Color(0xFFFFFFFF);
    }
    return dark
        ? const Color(0xFF1A2750).withValues(alpha: 0.85)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.95);
  }

  static Color glassBorderHighlight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.90);

  static Color glassBorderDim(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF26345E).withValues(alpha: 0.40)
          : const Color(0xFFE6EDFA);

  static const Color glassShadow = Color(0x140B1B4D);
  static const double glassBlurSigma = 12;
  static const double glassBlurSigmaHeavy = 16;

  static const Color gold = Color(0xFFEE7A2B);
  static const Color surfaceDark = Color(0xFF131E42);
  static const Color cardOverlay = Color(0x330B1B4D);

  /// The category-accent set. Everything that needs to tell one card apart
  /// from the next draws from these rather than inventing a hex. Blue, violet
  /// and cyan are the logo's three stops; teal/green/orange are kept only for
  /// meaning (ready/verified, success, streak fire, awards, warnings).
  static const Color accentBlue = Color(0xFF1A66E6);
  static const Color accentViolet = brandViolet;
  static const Color accentCyan = Color(0xFF0A7AC0);
  static const Color accentTeal = Color(0xFF0FA37F);
  static const Color accentOrange = Color(0xFFEE7A2B);
  static const Color accentGreen = Color(0xFF12A06A);
  static const Color accentSlate = Color(0xFF8290AE);

  // Learning mode accents — one logo stop each.
  static const Color learnColor = accentViolet;
  static const Color practiceColor = accentBlue;
  static const Color createColor = accentCyan;

  /// Also carries "verified / ready" states across the app, so it stays green.
  static const Color teachColor = accentTeal;

  // Domain category colors
  static const Color technologyColor = accentBlue;
  static const Color businessColor = accentTeal;
  static const Color academicColor = Color(0xFF7C4DFF);
  static const Color agricultureColor = accentGreen;
  static const Color lifeSkillsColor = accentCyan;

  static const Color online = accentTeal;
  static const Color offline = accentSlate;

  /// Hero/card text wash over decorative PNG — brightness-aware.
  static List<Color> heroOverlayColors(BuildContext context) {
    if (of(context).isDark) {
      return [
        const Color(0xFF0A1330).withValues(alpha: 0.82),
        const Color(0xFF0A1330).withValues(alpha: 0.55),
        const Color(0xFF0A1330).withValues(alpha: 0.20),
        Colors.transparent,
      ];
    }
    return [
      Colors.white.withValues(alpha: 0.92),
      Colors.white.withValues(alpha: 0.72),
      Colors.white.withValues(alpha: 0.35),
      Colors.transparent,
    ];
  }

  static const LinearGradient primaryButtonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accentBlue, Color(0xFF5A12E6)],
  );

  static const LinearGradient fabGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandCyan, Color(0xFF5A12E6)],
  );

  /// The logo's signature emphasis gradient — headline accents, stage bars,
  /// and anything that should read as the brand rather than as a surface.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandCyan, Color(0xFF0A6CE9), Color(0xFF5A12E6)],
  );

  /// The student's own chat bubble: a soft wash of the logo's blue→violet
  /// with navy ink, rather than a solid brand fill that shouts over the reply.
  static LinearGradient userBubbleGradient(BuildContext context) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: of(context).isDark
            ? const [Color(0xFF1B2B5C), Color(0xFF22215A)]
            : const [Color(0xFFEAF2FE), Color(0xFFF0EBFE)],
      );

  static Color userBubbleBorder(BuildContext context) =>
      of(context).isDark ? const Color(0xFF2C3B70) : const Color(0xFFD9E4FB);

  List<BoxShadow> softShadow(bool isDark) => isDark
      ? const []
      : const [
          BoxShadow(
            color: glassShadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ];

  List<BoxShadow> navShadow(bool isDark) => isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x1A0B1B4D),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ];
}
