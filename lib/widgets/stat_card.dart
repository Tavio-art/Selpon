import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.iconColor,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sari = context.sari;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = selected ? scheme.primary : sari.cardBorder;
    final fill = selected
        ? scheme.primary.withValues(alpha: 0.10)
        : sari.cardSurface;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: sari.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? scheme.primary,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.outfit(
                color: valueColor ?? scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
    );
  }
}
