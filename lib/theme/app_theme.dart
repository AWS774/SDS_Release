import 'package:flutter/material.dart';

class AppTheme {
  // ── Light mode colors ──────────────────────────────────────────────────────
  static const Color lightPrimaryBlue = Color(0xFF2563EB);
  static const Color lightPrimaryDark = Color(0xFF1E40AF);
  static const Color lightBackground = Color(0xFFF1F5F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);

  // ── Dark mode colors (biru gelap, nyaman di mata) ──────────────────────────
  // Background: navy gelap (bukan hitam pekat)
  static const Color darkBackground = Color(0xFF0F172A); // slate-900
  static const Color darkSurface = Color(0xFF1E293B); // slate-800
  static const Color darkCard = Color(0xFF1E293B); // slate-800
  static const Color darkCardElevated = Color(
    0xFF273549,
  ); // sedikit lebih terang
  static const Color darkPrimaryBlue = Color(
    0xFF3B82F6,
  ); // biru lebih cerah di dark
  static const Color darkPrimaryDark = Color(0xFF2563EB);
  static const Color darkTextPrimary = Color(0xFFF1F5F9); // slate-100
  static const Color darkTextSecondary = Color(0xFF94A3B8); // slate-400
  static const Color darkDivider = Color(0xFF334155); // slate-700
  static const Color darkInputFill = Color(0xFF273549);

  // ── Shared semantic colors ─────────────────────────────────────────────────
  static const Color successGreen = Color(0xFF10B981);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color warningAmber = Color(0xFFF59E0B);

  // ── ThemeData light ────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: lightPrimaryBlue,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: lightBackground,
    cardColor: lightCard,
    dividerColor: const Color(0xFFE2E8F0),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightPrimaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: lightCard,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? lightPrimaryBlue
                : Colors.grey.shade400,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? lightPrimaryBlue.withValues(alpha: 0.4)
                : Colors.grey.shade300,
      ),
    ),
  );

  // ── ThemeData dark ─────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: darkPrimaryBlue,
      brightness: Brightness.dark,
      surface: darkSurface,
    ).copyWith(surface: darkSurface, onSurface: darkTextPrimary),
    scaffoldBackgroundColor: darkBackground,
    cardColor: darkCard,
    dividerColor: darkDivider,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSurface,
      foregroundColor: darkTextPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkDivider, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkInputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: darkDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: darkDivider),
      ),
      hintStyle: const TextStyle(color: darkTextSecondary),
      labelStyle: const TextStyle(color: darkTextSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: darkCardElevated,
      surfaceTintColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? darkPrimaryBlue
                : Colors.grey.shade600,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? darkPrimaryBlue.withValues(alpha: 0.5)
                : Colors.grey.shade800,
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: darkTextPrimary),
      bodyMedium: TextStyle(color: darkTextPrimary),
      bodySmall: TextStyle(color: darkTextSecondary),
      titleLarge: TextStyle(
        color: darkTextPrimary,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(color: darkTextPrimary),
      titleSmall: TextStyle(color: darkTextSecondary),
    ),
    iconTheme: const IconThemeData(color: darkTextSecondary),
    listTileTheme: const ListTileThemeData(
      textColor: darkTextPrimary,
      iconColor: darkTextSecondary,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: darkCardElevated,
      contentTextStyle: TextStyle(color: darkTextPrimary),
    ),
  );
}
