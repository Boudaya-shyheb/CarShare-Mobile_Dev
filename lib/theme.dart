import 'package:flutter/material.dart';

const carShareGreen = Color(0xFF059669);
const carShareGreenDark = Color(0xFF065F46); // second stop of the green header gradients

// Support module palette (used by lib/pages/support and the support_* widgets).
// The two greens are now the brand greens (they were #079B70 and #047857, a shade off).
const supportGreen = carShareGreen;
const supportDarkGreen = carShareGreenDark;
const supportWarningBackground = Color(0xFFFFF1C2);
const supportWarningText = Color(0xFFD97706);

// Reservation module palette. Added alongside the existing colours, not in place of them:
// the user module's screens keep carShareGreen and the 14 px field radius above.
const carShareTint = Color(0xFFD1FAE5); // chips, badges, the "me" halo
const carShareSuccess = Color(0xFF10B981);
const carShareWarning = Color(0xFFF59E0B);
const carShareWarningTint = Color(0xFFFEF3C7); // the default avatar's background
const carShareDanger = Color(0xFFEF4444);
const carShareDangerTint = Color(0xFFFEE2E2); // Log out and delete icons
const carShareText = Color(0xFF0F172A);
const carShareMuted = Color(0xFF64748B);
const carShareBackground = Color(0xFFF5F7FB); // page and search-card background
const carShareBorder = Color(0xFFE2E8F0);

/// Card corner radius used across the reservation screens.
const carShareCardRadius = 20.0;

/// Height and corner radius of the reservation module's buttons.
const carShareButtonHeight = 56.0;
const carShareButtonRadius = 16.0;

/// The soft shadow under the floating cards on the map.
const carShareCardShadow = BoxShadow(
  color: Color(0x14000000),
  blurRadius: 24,
  offset: Offset(0, 8),
);

final carShareTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: carShareGreen,
    primary: carShareGreen,
  ),
  scaffoldBackgroundColor: Colors.white,
  fontFamily: 'PlusJakartaSans',
  // One AppBar for every screen: white, flat, bold dark title, no Material 3 tint on scroll.
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: carShareText,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: carShareText,
    ),
  ),
  // Cards (the admin lists use the plain Card widget): white, hairline border, 16 px corners.
  cardTheme: CardThemeData(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: carShareBorder),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(64, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: carShareGreen,
      side: const BorderSide(color: carShareBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: carShareTint,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: states.contains(WidgetState.selected)
            ? carShareGreen
            : carShareMuted,
      ),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    titleTextStyle: const TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: carShareText,
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: carShareGreen,
    foregroundColor: Colors.white,
  ),
  // The trunk-size / plate-type selectors: a tinted track with the chosen option in brand green.
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? carShareGreen
            : carShareBackground,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : carShareMuted,
      ),
      side: const WidgetStatePropertyAll(BorderSide.none),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w700),
      ),
    ),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: const WidgetStatePropertyAll(Colors.white),
    trackColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected) ? carShareGreen : carShareBorder,
    ),
    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
  ),
  dividerTheme: const DividerThemeData(color: carShareBorder, space: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE4E9)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE4E9)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: carShareGreen, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  ),
);
