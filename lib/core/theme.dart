// lib/core/theme.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

// ----------------------------------------------------------
//  THEME EXTENSION
// ----------------------------------------------------------
class DoodleBackgroundTheme extends ThemeExtension<DoodleBackgroundTheme> {
  final Color primaryColor;
  final Color secondaryColor;
  final double patternDensity;

  const DoodleBackgroundTheme({
    required this.primaryColor,
    required this.secondaryColor,
    required this.patternDensity,
  });

  @override
  ThemeExtension<DoodleBackgroundTheme> copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    double? patternDensity,
  }) {
    return DoodleBackgroundTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      patternDensity: patternDensity ?? this.patternDensity,
    );
  }

  @override
  ThemeExtension<DoodleBackgroundTheme> lerp(
    ThemeExtension<DoodleBackgroundTheme>? other,
    double t,
  ) {
    if (other is! DoodleBackgroundTheme) return this;
    return DoodleBackgroundTheme(
      primaryColor: Color.lerp(primaryColor, other.primaryColor, t)!,
      secondaryColor: Color.lerp(secondaryColor, other.secondaryColor, t)!,
      patternDensity: lerpDouble(patternDensity, other.patternDensity, t)!,
    );
  }
}

// ----------------------------------------------------------
//  BACKGROUND WIDGET (With Blur Integration)
// ----------------------------------------------------------
class DoodleBackground extends StatelessWidget {
  final Widget child;

  const DoodleBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Default to the Green Theme if extension is missing
    final theme = Theme.of(context).extension<DoodleBackgroundTheme>() ??
        const DoodleBackgroundTheme(
          primaryColor: Color(0xFF00E676), // Neon Green
          secondaryColor: Color(0xFF00B0FF), // Cyan
          patternDensity: 1.0,
        );

    return Stack(
      children: [
        // The Pattern
        CustomPaint(
          painter: DoodlePainter(
            primaryColor: theme.primaryColor,
            secondaryColor: theme.secondaryColor,
            density: theme.patternDensity,
          ),
          size: Size.infinite,
        ),
        // Subtle Backdrop Blur for "Glass" feel
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
          child: Container(color: Colors.transparent),
        ),
        child,
      ],
    );
  }
}

// ----------------------------------------------------------
//  CUSTOM PAINTER (Optimized for Dark Mode)
// ----------------------------------------------------------
class DoodlePainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final double density;

  DoodlePainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.density,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint()..style = PaintingStyle.stroke;

    // Tech Lines
    for (int i = 0; i < (size.width * size.height * density / 12000); i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final length = 30 + random.nextDouble() * 50;

      // Lower opacity for dark mode subtlety
      paint.color = random.nextBool()
          ? primaryColor.withOpacity(0.08)
          : secondaryColor.withOpacity(0.08);
      paint.strokeWidth = 1 + random.nextDouble() * 1.5;

      final path = Path();
      path.moveTo(startX, startY);
      double currentX = startX;
      double currentY = startY;

      // More angular, "tech" looking lines
      for (int j = 0; j < 4; j++) {
        currentX += (random.nextDouble() - 0.5) * length;
        currentY += (random.nextDouble() - 0.5) * length;
        path.lineTo(currentX, currentY);
      }
      canvas.drawPath(path, paint);
    }

    // Glowing Orbs
    for (int i = 0; i < (size.width * size.height * density / 15000); i++) {
      final centerX = random.nextDouble() * size.width;
      final centerY = random.nextDouble() * size.height;
      final radius = 1 + random.nextDouble() * 4;

      paint.color = random.nextBool()
          ? primaryColor.withOpacity(0.15)
          : secondaryColor.withOpacity(0.15);
      paint.style = PaintingStyle.fill;
      
      // Add a simple glow effect by drawing twice
      canvas.drawCircle(Offset(centerX, centerY), radius * 2, 
        Paint()..color = paint.color.withOpacity(0.05));
      canvas.drawCircle(Offset(centerX, centerY), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}