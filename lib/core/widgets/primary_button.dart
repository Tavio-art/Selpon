import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sari_storefront.dart';

class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 58,
    this.borderRadius = 32,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double borderRadius;
  final bool isLoading;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.97,
      upperBound: 1,
      value: 1,
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _down() {
    if (!sariAnimationsEnabled(context)) return;
    _scale.reverse();
  }

  void _up() {
    if (!sariAnimationsEnabled(context)) return;
    _scale.forward();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: ScaleTransition(
        scale: _scale,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: ElevatedButton(
            onPressed: widget.isLoading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              disabledBackgroundColor: scheme.primary.withValues(alpha: 0.7),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              textStyle: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: widget.isLoading
                ? SizedBox(
                    width: 23,
                    height: 23,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: scheme.onPrimary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 20,
                          color: scheme.onPrimary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(widget.label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
