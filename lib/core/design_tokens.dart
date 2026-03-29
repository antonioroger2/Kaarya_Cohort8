// lib/core/design_tokens.dart
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  App Design Tokens
// ─────────────────────────────────────────────
class AppDesignTokens {
  // Colors
  static const Color primary = Color(0xFF00897B);
  static const Color accent = Color(0xFF26A69A);
  static const Color aiBlue = Color(0xFF1E88E5);
  static const Color surface = Color(0xFFF7FAFA);
  static const Color cardBg = Colors.white;
  static const Color success = Color(0xFF43A047);
  static const Color danger = Color(0xFFEF5350);
  static const Color warning = Color(0xFFFF8F00);
  static const Color info = Color(0xFF1E88E5);
  static const Color text1 = Color(0xFF263238);
  static const Color text2 = Color(0xFF546E7A);
  static const Color tileSelected = Color(0xFFE1F5EE);
  static const Color lightGrey = Color(0xFFEEEEEE);

  // Radii
  static const Radius radius = Radius.circular(16);
  static const Radius radiusSm = Radius.circular(10);
  static const Radius cardRadius = Radius.circular(16); // Standardized to 16

  // Paddings
  static const EdgeInsets cardPad = EdgeInsets.all(20);
  static const EdgeInsets pagePad = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  // Box Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0C000000), blurRadius: 14, offset: Offset(0, 4))
  ];

  // Decorations
  static BoxDecoration cardDecoration({Color? borderColor}) => BoxDecoration(
    color: cardBg,
    borderRadius: BorderRadius.all(cardRadius),
    border: borderColor != null
        ? Border.all(color: borderColor.withOpacity(0.3), width: 1.2)
        : null,
    boxShadow: cardShadow,
  );

  static InputDecoration fieldDecoration({
    required String label,
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        labelStyle: const TextStyle(fontSize: 13.5, color: text2),
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF4F8F8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(radiusSm),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(radiusSm),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(radiusSm),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
      );
}