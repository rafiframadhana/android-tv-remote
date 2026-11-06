import 'package:flutter/material.dart';

/// The screen is the remote's body: graphite-blue plastic, raised keys,
/// one amber "standby LED" accent for press and focus.
abstract final class RemoteColors {
  static const body = Color(0xFF1A2030);
  static const key = Color(0xFF283044);
  static const keyPressed = Color(0xFF323B52);
  static const keyEdge = Color(0xFF39435C);
  static const text = Color(0xFFE8EBF2);
  static const muted = Color(0xFF8A93A8);
  static const led = Color(0xFFF0B23E);
  static const power = Color(0xFFE5484D);
  static const ok = Color(0xFF4CC38A);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: RemoteColors.led, brightness: Brightness.dark).copyWith(
    surface: RemoteColors.body,
    onSurface: RemoteColors.text,
    primary: RemoteColors.led,
    onPrimary: RemoteColors.body,
    surfaceContainerHigh: RemoteColors.key,
    surfaceContainerHighest: RemoteColors.keyPressed,
    error: RemoteColors.power,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: RemoteColors.body,
    appBarTheme: const AppBarTheme(
      backgroundColor: RemoteColors.body,
      foregroundColor: RemoteColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: RemoteColors.led,
      foregroundColor: RemoteColors.body,
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF20273A), showDragHandle: true),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: RemoteColors.text, height: 1.4),
      bodySmall: TextStyle(color: RemoteColors.muted, height: 1.4),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}
