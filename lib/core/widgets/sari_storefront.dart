import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Fixed brand decorations allowed outside theme tokens.
abstract final class SariBrandDecor {
  static const Color cream = Color(0xFFFFF6DF);
  static const Color marigold = Color(0xFFF2A900);
  static const Color shelfRed = Color(0xFFD9482B);
  static const Color shelfTan = Color(0xFFE8D9B0);
  static const Color onGreen = Color(0xFFFFF6DF);

  /// Auth/splash header green (existing light primary brand).
  static const Color headerGreen = AppColors.lightPrimary;
}

class SariLogo extends StatelessWidget {
  const SariLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.23;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/sari_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: SariBrandDecor.cream,
            borderRadius: BorderRadius.circular(radius),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.storefront_rounded,
            color: SariBrandDecor.headerGreen,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}

/// Full-width awning: 6 vertical stripes + scallops. Height ~103.
class SariAwning extends StatelessWidget {
  const SariAwning({super.key, this.height = 103});

  final double height;

  @override
  Widget build(BuildContext context) {
    const colors = [
      SariBrandDecor.cream,
      SariBrandDecor.marigold,
      SariBrandDecor.cream,
      SariBrandDecor.marigold,
      SariBrandDecor.cream,
      SariBrandDecor.marigold,
    ];
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in colors)
                  Expanded(child: ColoredBox(color: c)),
              ],
            ),
          ),
          SizedBox(
            height: 18,
            child: Row(
              children: [
                for (final c in colors)
                  Expanded(
                    child: CustomPaint(
                      painter: _ScallopPainter(c),
                      size: const Size(double.infinity, 18),
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

class _ScallopPainter extends CustomPainter {
  _ScallopPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // Semicircle hanging down from the stripe.
    final oval = Rect.fromLTWH(0, -size.height, size.width, size.height * 2);
    canvas.drawArc(oval, 0, math.pi, true, paint);
  }

  @override
  bool shouldRepaint(covariant _ScallopPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Shelf items drawn with CustomPainter on a dark line.
class SariShelfPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lineY = size.height - 6;
    final line = Paint()
      ..color = AppColors.darkGreenTop
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(8, lineY), Offset(size.width - 8, lineY), line);

    final cx = size.width / 2;
    final items = <void Function()>[
      () => _can(canvas, cx - 118, lineY, SariBrandDecor.shelfRed),
      () => _bottle(canvas, cx - 78, lineY, SariBrandDecor.marigold),
      () => _chips(canvas, cx - 40, lineY, SariBrandDecor.cream),
      () => _jar(canvas, cx, lineY, SariBrandDecor.shelfTan),
      () => _noodle(canvas, cx + 38, lineY, SariBrandDecor.shelfRed),
      () => _sack(canvas, cx + 78, lineY, SariBrandDecor.cream),
      () => _can(canvas, cx + 118, lineY, SariBrandDecor.marigold),
    ];
    for (final draw in items) {
      draw();
    }
  }

  void _can(Canvas canvas, double x, double base, Color color) {
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, base - 16), width: 18, height: 28),
      const Radius.circular(3),
    );
    canvas.drawRRect(r, Paint()..color = color);
    canvas.drawLine(
      Offset(x - 7, base - 22),
      Offset(x + 7, base - 22),
      Paint()
        ..color = SariBrandDecor.onGreen.withValues(alpha: 0.55)
        ..strokeWidth = 2,
    );
  }

  void _bottle(Canvas canvas, double x, double base, Color color) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, base - 14), width: 14, height: 22),
      const Radius.circular(4),
    );
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, base - 28), width: 8, height: 10),
        const Radius.circular(2),
      ),
      Paint()..color = color.withValues(alpha: 0.85),
    );
  }

  void _chips(Canvas canvas, double x, double base, Color color) {
    final path = Path()
      ..moveTo(x - 12, base - 4)
      ..quadraticBezierTo(x - 14, base - 30, x, base - 34)
      ..quadraticBezierTo(x + 14, base - 30, x + 12, base - 4)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(
      Offset(x, base - 18),
      4,
      Paint()..color = SariBrandDecor.marigold,
    );
  }

  void _jar(Canvas canvas, double x, double base, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, base - 14), width: 20, height: 24),
        const Radius.circular(6),
      ),
      Paint()..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, base - 28), width: 16, height: 6),
        const Radius.circular(2),
      ),
      Paint()..color = SariBrandDecor.marigold,
    );
  }

  void _noodle(Canvas canvas, double x, double base, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, base - 12), width: 22, height: 18),
        const Radius.circular(4),
      ),
      Paint()..color = color,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, base - 22), width: 22, height: 8),
      Paint()..color = SariBrandDecor.cream,
    );
  }

  void _sack(Canvas canvas, double x, double base, Color color) {
    final path = Path()
      ..moveTo(x - 14, base - 4)
      ..lineTo(x - 12, base - 26)
      ..quadraticBezierTo(x, base - 32, x + 12, base - 26)
      ..lineTo(x + 14, base - 4)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SariShelf extends StatelessWidget {
  const SariShelf({super.key, this.height = 56});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: SariShelfPainter()),
    );
  }
}

class SariPulseDots extends StatelessWidget {
  const SariPulseDots({super.key, required this.t});

  /// 0..1 pulse phase.
  final double t;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final phase = (t + i * 0.22) % 1.0;
        final scale = 0.7 + 0.3 * math.sin(phase * math.pi * 2).abs();
        final opacity = 0.45 + 0.55 * scale;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity.clamp(0.35, 1.0),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: SariBrandDecor.marigold,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

TextStyle sariOnGreenTitle(double size, {FontWeight weight = FontWeight.w800}) {
  return GoogleFonts.outfit(
    color: SariBrandDecor.onGreen,
    fontSize: size,
    fontWeight: weight,
    height: 1.1,
  );
}

/// Skip motion when accessibility disables animations.
bool sariAnimationsEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

class FirstBuildFadeIn extends StatefulWidget {
  const FirstBuildFadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
  });

  final Widget child;
  final Duration duration;

  @override
  State<FirstBuildFadeIn> createState() => _FirstBuildFadeInState();
}

class _FirstBuildFadeInState extends State<FirstBuildFadeIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _controller != null) return;
    if (!sariAnimationsEnabled(context)) {
      _done = true;
      return;
    }
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward().whenComplete(() {
        _done = true;
        _controller?.dispose();
        _controller = null;
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || _done) return widget.child;
    return FadeTransition(opacity: c, child: widget.child);
  }
}
