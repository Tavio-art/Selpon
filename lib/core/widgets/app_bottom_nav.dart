import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  /// Pill bar height inside [AppBottomNav].
  static const double barHeight = 72;

  /// Bottom padding under the pill (see [build]).
  static const double bottomPadding = 12;

  /// Scan FAB is `Transform.translate`d up by this amount above the bar.
  static const double scanOvershoot = 12;

  /// Clear air between content/popups and the top of the Scan FAB.
  static const double clearGap = 14;

  /// Floating nav chrome above the system bottom inset:
  /// bar + bottom padding + Scan FAB overshoot.
  static const double chromeHeight =
      barHeight + bottomPadding + scanOvershoot; // 96

  /// True system/gesture inset. Use [viewPadding] — with
  /// [Scaffold.extendBody] true, [MediaQuery.padding.bottom] is inflated to
  /// the bottomNavigationBar height and must not be reused as "system" inset.
  static double systemBottomInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  /// Physical screen bottom → top of the Scan FAB.
  static double occupiedHeight(BuildContext context) =>
      systemBottomInset(context) + chromeHeight;

  /// Bottom inset for full-bleed stacks (body draws under the nav;
  /// SafeArea bottom: false). Counts chrome once from viewPadding.
  static double bodyBottomInset(BuildContext context) =>
      occupiedHeight(context) + clearGap;

  /// Extra scroll/overlay inset when SafeArea (or extendBody MediaQuery
  /// padding) already cleared the nav bar layout height — only Scan
  /// overshoot + gap remain.
  static double safeBodyBottomInset() => scanOvershoot + clearGap;

  /// Bottom offset for floating toasts/SnackBars above the nav + Scan FAB.
  /// Use when the overlay is positioned against the physical screen bottom
  /// (SafeArea bottom: false / full-bleed stack).
  static double toastBottomInset(BuildContext context) =>
      bodyBottomInset(context);

  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sari = context.sari;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    final items = [
      (
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: l10n.text('navHome'),
      ),
      (
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        label: l10n.text('navInventory'),
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
        selectedIcon: Icons.qr_code_scanner_rounded,
        label: l10n.text('navScan'),
      ),
      (
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart_rounded,
        label: l10n.text('navDashboard'),
      ),
      (
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: l10n.text('navProfile'),
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, bottomPadding),
        child: Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: sari.navBarBackground,
            borderRadius: BorderRadius.circular(38),
            border: Border.all(
              color: sari.navBarBorder,
              width: 1,
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: sari.shadow,
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = currentIndex == index;
              final isScan = index == 2;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: isScan
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -scanOvershoot),
                              child: Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: sari.navBarScanBg,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: sari.shadow,
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  item.icon,
                                  color: sari.navBarScanFg,
                                  size: 26,
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -6),
                              child: Text(
                                item.label,
                                style: GoogleFonts.outfit(
                                  color: selected
                                      ? scheme.primary
                                      : sari.faintText,
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                AnimatedScale(
                                  scale: selected ? 1.08 : 1.0,
                                  duration: MediaQuery.disableAnimationsOf(
                                          context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                    selected
                                        ? item.selectedIcon
                                        : item.icon,
                                    color: selected
                                        ? scheme.primary
                                        : sari.faintText,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            AnimatedDefaultTextStyle(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              style: GoogleFonts.outfit(
                                color: selected
                                    ? scheme.primary
                                    : sari.faintText,
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              child: Text(item.label),
                            ),
                          ],
                        ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
