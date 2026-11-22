// //Added By Nikhil 18Nov26 21:32 For G.One.X Light Theme
import 'package:flutter/material.dart';
//Removed By Nikhil 21Nov26 21:16 For bundled fonts: import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF10B981); //Modified By Nikhil 21Nov26 21:00 For design --primary. Old: Color(0xFF00C896)
  static const Color primaryDark = Color(0xFF059669); //Modified By Nikhil 21Nov26 21:00 For design --primary-dark. Old: Color(0xFF00A87D)
  static const Color darkBg = Color(0xFF030712);
  static const Color lightBg = Color(0xFFF3F5F9);
  static const Color cardSurface = Colors.white;
  static const Color cardBorder = Color(0xFFF1F5F9);

  static const Color accentGold = Color(0xFFF59E0B);
  static const Color pillDark = Color(0xFF0F172A);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textSubtle = Color(0xFF94A3B8);
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEF2F2);
  static const Color warningOrange = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color successGreen = Color(0xFF10B981);
  static const Color successLight = Color(0xFFECFDF5);

  //Added By Nikhil 21Nov26 21:00 For design tokens from ui_prototype_docspot START
  static const Color screenBg = Colors.white; // .phone background
  static const Color cardSubtle = Color(0xFFF8FAFC); // --bg-card-subtle
  static const Color borderSubtle = Color(0xFFE2E8F0); // --border-subtle
  static const Color chipBg = Color(0xFFF1F5F9);
  static const Color label = Color(0xFF475569);
  static const Color secondaryText = Color(0xFF334155);
  static const Color accentBlue = Color(0xFF2563EB); // --accent
  static const Color selectedBg = Color(0xFFF0FDF4);
  static const double radiusLg = 24;
  static const double radiusMd = 16;
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 25, spreadRadius: -5, offset: Offset(0, 10)),
  ];
  //Added By Nikhil 21Nov26 21:00 For design tokens from ui_prototype_docspot END

  static ThemeData get lightTheme {
    //Added By Nikhil 21Nov26 21:00 For design font + input style START
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: borderSubtle),
    );
    //Added By Nikhil 21Nov26 21:00 For design font + input style END
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: screenBg, //Modified By Nikhil 21Nov26 21:00 For white phone background. Old: lightBg
      primaryColor: primary,
      fontFamily: 'PlusJakartaSans', //Modified By Nikhil 21Nov26 21:16 For bundled font family (all weights). Old: GoogleFonts.plusJakartaSans().fontFamily
      textTheme: base.textTheme.apply(fontFamily: 'PlusJakartaSans', bodyColor: textPrimary, displayColor: textPrimary), //Modified By Nikhil 21Nov26 21:16 For font on every text style (base theme carries Roboto). Old: base.textTheme.apply(bodyColor: textPrimary, displayColor: textPrimary)
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'PlusJakartaSans'), //Added By Nikhil 21Nov26 21:16 For font on primary text styles
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary, //Added By Nikhil 21Nov26 21:00 For exact design green
        surface: screenBg, //Modified By Nikhil 21Nov26 21:00 For white surfaces. Old: lightBg
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      //Added By Nikhil 21Nov26 21:00 For .doc-input style START
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardSubtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        hintStyle: const TextStyle(color: textSubtle, fontSize: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: textPrimary)),
        errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: errorRed)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: errorRed)),
        counterStyle: const TextStyle(height: 0, fontSize: 0),
      ),
      //Added By Nikhil 21Nov26 21:00 For .doc-input style END
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pillDark,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      //Added By Nikhil 21Nov26 21:00 For design-style snackbars START
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: pillDark,
        shape: StadiumBorder(),
      ),
      //Added By Nikhil 21Nov26 21:00 For design-style snackbars END
    );
  }
}
