import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../services/cart_store.dart';
import '../../services/settings_store.dart';
import '../theme/app_theme.dart';
import 'app_bottom_nav.dart';

/// Shared "Added to Cart" toast used by Home and Scan.
class CartAddedPopup extends StatelessWidget {
  final String productName;
  final int quantity;
  final VoidCallback onViewCart;

  /// When true, [bottom] is measured inside an existing bottom [SafeArea].
  final bool insideSafeArea;
  final bool showCartAction;
  final double bottomOffset;

  const CartAddedPopup({
    super.key,
    required this.productName,
    required this.quantity,
    required this.onViewCart,
    this.insideSafeArea = true,
    this.showCartAction = true,
    this.bottomOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final sari = context.sari;
    final scheme = Theme.of(context).colorScheme;
    // Home draws under the floating nav (SafeArea bottom: false) so the toast
    // must clear bar + Scan FAB. Nested SafeArea screens only need the FAB gap.
    final bottom = insideSafeArea
        ? AppBottomNav.safeBodyBottomInset() + 8
        : AppBottomNav.toastBottomInset(context);
    final name = productName.trim().isNotEmpty ? productName.trim() : 'Item';

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom + bottomOffset,
      child: ListenableBuilder(
        listenable: showCartAction
            ? Listenable.merge([CartStore.instance, SettingsStore.instance])
            : SettingsStore.instance,
        builder: (context, _) {
          final cartItemCount = CartStore.instance.itemCount;
          final cartSubtotal = CartStore.instance.subtotal;

          return Material(
            color: Colors.transparent,
            elevation: 8,
            shadowColor: sari.shadow,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                color: sari.cardSurfaceStrong,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: sari.cardBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: sari.shadow,
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: sari.accentAmber.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: sari.accentAmber,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.text(
                            'addedToCartMessage',
                            values: {
                              'quantity': '$quantity',
                              'name': name,
                            },
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showCartAction) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: onViewCart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sari.accentAmber,
                          foregroundColor: sari.onAccentAmber,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.text(
                                  cartItemCount > 1
                                      ? 'viewCartItemsPlural'
                                      : 'viewCartItems',
                                  values: {'count': '$cartItemCount'},
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              SettingsStore.instance.formatMoney(cartSubtotal),
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
