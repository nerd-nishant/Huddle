import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// HUDDLE palette: deep midnight + electric violet, with lime / pink / sky pops.
class HC {
  static const violet = Color(0xFF8B5CF6);
  static const violetSoft = Color(0xFFB69CFF);
  static const lime = Color(0xFFC6F432);
  static const pink = Color(0xFFFF7AC6);
  static const peach = Color(0xFFFFB38A);
  static const sky = Color(0xFF6EE7F9);
  static const ink = Color(0xFF0E0B16);
  static const card = Color(0xFF181326);
  static const card2 = Color(0xFF231C35);

  static const grad = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFFF7AC6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const gradLime = LinearGradient(
    colors: [Color(0xFFC6F432), Color(0xFF6EE7F9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData huddleTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: HC.violet, brightness: b).copyWith(
    primary: dark ? HC.violetSoft : HC.violet,
    onPrimary: dark ? HC.ink : Colors.white,
    secondary: HC.lime,
    onSecondary: HC.ink,
    surface: dark ? HC.ink : const Color(0xFFF8F6FF),
    onSurface: dark ? const Color(0xFFF1ECFF) : const Color(0xFF1A1330),
    surfaceContainer: dark ? HC.card : Colors.white,
    surfaceContainerHigh: dark ? HC.card2 : const Color(0xFFEFEAFF),
    outlineVariant: dark ? const Color(0xFF3A3053) : const Color(0xFFDDD5F5),
  );
  final base = ThemeData(brightness: b, colorScheme: cs, useMaterial3: true);
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
      .apply(bodyColor: cs.onSurface, displayColor: cs.onSurface);
  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle:
          text.titleLarge!.copyWith(fontWeight: FontWeight.w800, fontSize: 22),
    ),
    cardTheme: CardThemeData(
      color: cs.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainer,
      indicatorColor: HC.violet.withOpacity(.25),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall!.copyWith(fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: HC.violet, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HC.violet,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide.none,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
