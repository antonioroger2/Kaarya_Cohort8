// lib/core/theme.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

// 1. ThemeExtension
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
    if (other is! DoodleBackgroundTheme) {
      return this;
    }
    return DoodleBackgroundTheme(
      primaryColor: Color.lerp(primaryColor, other.primaryColor, t)!,
      secondaryColor: Color.lerp(secondaryColor, other.secondaryColor, t)!,
      patternDensity: lerpDouble(patternDensity, other.patternDensity, t)!,
    );
  }
}

// 2. Background Widget
class DoodleBackground extends StatelessWidget {
  final Widget child;

  const DoodleBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<DoodleBackgroundTheme>();
    if (theme == null) return child;

    return Stack(
      children: [
        CustomPaint(
          painter: DoodlePainter(
            primaryColor: theme.primaryColor,
            secondaryColor: theme.secondaryColor,
            density: theme.patternDensity,
          ),
          size: Size.infinite,
        ),
        child,
      ],
    );
  }
}

// 3. Custom Painter
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
    final random = math.Random(42); // Fixed seed for consistent pattern
    final paint = Paint()..style = PaintingStyle.stroke;

    // Draw squiggly lines
    for (int i = 0; i < (size.width * size.height * density / 10000); i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final length = 20 + random.nextDouble() * 40;

      paint.color = random.nextBool() ? primaryColor.withOpacity(0.1) : secondaryColor.withOpacity(0.1);
      paint.strokeWidth = 1 + random.nextDouble() * 2;

      final path = Path();
      path.moveTo(startX, startY);
      double currentX = startX;
      double currentY = startY;

      for (int j = 0; j < 5; j++) {
        currentX += (random.nextDouble() - 0.5) * length;
        currentY += (random.nextDouble() - 0.5) * length;
        path.lineTo(currentX, currentY);
      }
      canvas.drawPath(path, paint);
    }

    // Draw small circles
    for (int i = 0; i < (size.width * size.height * density / 20000); i++) {
      final centerX = random.nextDouble() * size.width;
      final centerY = random.nextDouble() * size.height;
      final radius = 2 + random.nextDouble() * 8;

      paint.color = random.nextBool() ? primaryColor.withOpacity(0.05) : secondaryColor.withOpacity(0.05);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), radius, paint);
    }

    // Draw small stars
    for (int i = 0; i < (size.width * size.height * density / 30000); i++) {
      final centerX = random.nextDouble() * size.width;
      final centerY = random.nextDouble() * size.height;
      final starSize = 3 + random.nextDouble() * 5;

      paint.color = random.nextBool() ? primaryColor.withOpacity(0.08) : secondaryColor.withOpacity(0.08);
      paint.strokeWidth = 1;
      _drawStar(canvas, centerX, centerY, 5, starSize, starSize / 2, paint);
    }
  }

  void _drawStar(Canvas canvas, double centerX, double centerY, int spikes, double outerRadius, double innerRadius, Paint paint) {
    final path = Path();
    final angle = math.pi / spikes;

    for (int i = 0; i < spikes * 2; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final x = centerX + math.cos(i * angle) * radius;
      final y = centerY + math.sin(i * angle) * radius;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
