import 'package:material_ui/material_ui.dart';

/// Thème pensé pour des personnes âgées : gros caractères, forts contrastes,
/// grandes zones tactiles.
const Color brand = Color(0xFF0B5D5E);
const Color okGreen = Color(0xFF1B6E2D);
const Color warnOrange = Color(0xFFA34700);
const Color ink = Color(0xFF14201F);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    primary: brand,
    surface: const Color(0xFFFAF8F4),
    onSurface: ink,
  );
  const buttonText = TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  const buttonSize = Size(double.infinity, 68);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: ink, height: 1.2),
      titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink),
      titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: ink),
      bodyLarge: TextStyle(fontSize: 21, color: ink, height: 1.35),
      bodyMedium: TextStyle(fontSize: 19, color: ink, height: 1.35),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      centerTitle: false,
      toolbarHeight: 72,
      titleTextStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink),
      iconTheme: const IconThemeData(size: 32, color: ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        textStyle: buttonText,
        shape: buttonShape,
        iconSize: 30,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        textStyle: buttonText,
        shape: buttonShape,
        iconSize: 30,
        side: const BorderSide(color: brand, width: 2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(20),
      labelStyle: const TextStyle(fontSize: 20),
      errorStyle: const TextStyle(fontSize: 18),
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ink, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF5E6B6A), width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFD5D2CA)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink),
      contentTextStyle: TextStyle(fontSize: 20, color: ink, height: 1.35),
    ),
  );
}
