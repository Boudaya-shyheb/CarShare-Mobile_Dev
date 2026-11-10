import 'package:flutter/material.dart';

const carShareGreen = Color(0xFF059669);
const supportGreen = Color(0xFF079B70);
const supportDarkGreen = Color(0xFF047857);
const supportWarningBackground = Color(0xFFFFF1C2);
const supportWarningText = Color(0xFFD97706);

// Reservation module palette. Added alongside the existing colours, not in place of them:
// the user module's screens keep carShareGreen and the 14 px field radius above.
const carShareTint = Color(0xFFD1FAE5); // chips, badges, the "me" halo
const carShareSuccess = Color(0xFF10B981);
const carShareWarning = Color(0xFFF59E0B);
const carShareDanger = Color(0xFFEF4444);
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
  fontFamily: 'Roboto',
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
