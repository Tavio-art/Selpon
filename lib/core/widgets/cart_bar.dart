import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

class CartBar extends StatelessWidget {
  static const double height = 56;

  final VoidCallback onTap;
  final double bottom;
  final int itemCount;
  final double subtotal;

  const CartBar({
    super.key,
    required this.onTap,
    required this.bottom,
    required this.itemCount,
    required this.subtotal,
  });

  @override
  Widget build(BuildContext context) {
    final sari = context.sari;
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final hasItems = itemCount > 0;
    final total = NumberFormat('#,##0.00', 'en_US').format(subtotal);

    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: !hasItems,
        child: ExcludeSemantics(
          excluding: !hasItems,
          child: AnimatedSlide(
            offset: hasItems ? Offset.zero : const Offset(0, 0.18),
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: hasItems ? 1 : 0,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: SizedBox(
                height: height,
                child: Material(
                  color: sari.accentAmber,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Center(
                                  child: Icon(
                                    Icons.shopping_cart_outlined,
                                    color: sari.onAccentAmber,
                                    size: 23,
                                  ),
                                ),
                                Positioned(
                                  top: -4,
                                  right: -5,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: sari.cardSurfaceStrong,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: sari.accentAmber,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      itemCount > 99 ? '99+' : '$itemCount',
                                      style: GoogleFonts.outfit(
                                        color: scheme.onSurface,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'View cart',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: sari.onAccentAmber,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '₱$total',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: GoogleFonts.outfit(
                                color: sari.onAccentAmber,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: sari.onAccentAmber,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
