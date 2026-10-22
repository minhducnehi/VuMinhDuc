import 'package:flutter/material.dart';

class AppTheme {
  // Brand Primary & Accents - Tươi sáng, Trẻ trung & Năng động
  static const Color primary = Color(0xFF4F46E5); // Indigo trẻ trung
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color secondary = Color(0xFF0EA5E9); // Sky Blue tươi mát
  static const Color accent = Color(0xFFF59E0B); // Amber ấm áp
  static const Color playful = Color(0xFFFF6B6B); // Coral năng động cho trẻ

  // Backgrounds & Surface (Sáng sủa, sạch sẽ, hiện đại)
  static const Color background = Color(0xFFF1F5F9); // Nền xám sữa sáng nhẹ
  static const Color surface = Color(0xFFFFFFFF); // Thẻ card trắng tinh
  static const Color surfaceElevated = Color(0xFFE2E8F0); // Xám sáng nổi bật
  static const Color surfaceLight = Color(0xFFF8FAFC);

  // Status Colors
  static const Color success = Color(0xFF10B981); // Xanh ngọc
  static const Color error = Color(0xFFEF4444); // Đỏ tươi
  static const Color warning = Color(0xFFF59E0B); // Cam vàng
  static const Color info = Color(0xFF3B82F6); // Xanh lam

  // Text Colors (Tương phản cao, dễ đọc trên nền sáng)
  static const Color textPrimary = Color(0xFF0F172A); // Slate đen đậm
  static const Color textSecondary = Color(0xFF475569); // Slate xám vừa
  static const Color textMuted = Color(0xFF94A3B8); // Slate nhạt

  // Gradients tươi trẻ
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient kidGradient = LinearGradient(
    colors: [Color(0xFFFF7E5F), Color(0xFFFEB47B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient adminGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // GIAO DIỆN SÁNG TƯƠI TRẺ, THÂN THIỆN GIA ĐÌNH
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      fontFamily: 'Segoe UI',
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shadowColor: const Color(0x15000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
        prefixIconColor: primary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Tương thích ngược nếu cần
  static ThemeData get darkTheme => lightTheme;
}
