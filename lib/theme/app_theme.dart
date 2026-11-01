import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF000000);
  static const Color surfaceCard = Color(0xFF0C0C0C);
  static const Color surfaceElevated = Color(0xFF141414);
  
  static const Color primaryPink = Color(0xFFEC4899);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRed = Color(0xFFEF4444);
  
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0x1AFFFFFF);
  static const Color borderMedium = Color(0x33FFFFFF);

  static Color parseHexColor(String hexString, {Color fallback = primaryPink}) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  static BoxDecoration glassPanel({
    double borderRadius = 16,
    Color? borderColor,
    Color? fillColor,
  }) {
    return BoxDecoration(
      color: fillColor ?? surfaceCard,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? borderLight,
        width: 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration glassPanelElevated({
    double borderRadius = 24,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: surfaceElevated,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? borderMedium,
        width: 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x80000000),
          blurRadius: 30,
          spreadRadius: 2,
          offset: Offset(0, 15),
        ),
      ],
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primaryPink,
      colorScheme: const ColorScheme.dark(
        primary: primaryPink,
        secondary: accentPurple,
        surface: surface,
        onSurface: textPrimary,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      iconTheme: const IconThemeData(
        color: textSecondary,
      ),
      useMaterial3: true,
    );
  }
}
