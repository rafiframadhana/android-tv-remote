import 'package:flutter/material.dart';

/// The screen is the remote's body: plastic with raised keys and one amber "standby LED" accent
/// for press and focus. Dark is graphite blue; light is a pale grey remote with white keys.
@immutable
class RemotePalette extends ThemeExtension<RemotePalette> {
  const RemotePalette({
    required this.body,
    required this.key,
    required this.keyPressed,
    required this.keyEdge,
    required this.text,
    required this.muted,
    required this.led,
    required this.onLed,
    required this.power,
    required this.ok,
    required this.sheet,
    required this.okKey,
  });

  final Color body;
  final Color key;
  final Color keyPressed;
  final Color keyEdge;
  final Color text;
  final Color muted;
  final Color led;

  /// Text/icons drawn on top of [led].
  final Color onLed;
  final Color power;
  final Color ok;
  final Color sheet;

  /// The OK disc in the middle of the D-pad (a shade apart from the ring).
  final Color okKey;

  static const dark = RemotePalette(
    body: Color(0xFF1A2030),
    key: Color(0xFF283044),
    keyPressed: Color(0xFF323B52),
    keyEdge: Color(0xFF39435C),
    text: Color(0xFFE8EBF2),
    muted: Color(0xFF8A93A8),
    led: Color(0xFFF0B23E),
    onLed: Color(0xFF1A2030),
    power: Color(0xFFE5484D),
    ok: Color(0xFF4CC38A),
    sheet: Color(0xFF20273A),
    okKey: Color(0xFF2F384E),
  );

  static const light = RemotePalette(
    body: Color(0xFFEEF0F4),
    key: Color(0xFFFFFFFF),
    keyPressed: Color(0xFFE2E6EE),
    keyEdge: Color(0xFFCDD3DE),
    text: Color(0xFF1A2030),
    muted: Color(0xFF5E6779),
    led: Color(0xFFC98A12),
    onLed: Color(0xFFFFFFFF),
    power: Color(0xFFD93A3F),
    ok: Color(0xFF2E9E68),
    sheet: Color(0xFFF7F8FA),
    okKey: Color(0xFFE6E9EF),
  );

  @override
  RemotePalette copyWith({
    Color? body,
    Color? key,
    Color? keyPressed,
    Color? keyEdge,
    Color? text,
    Color? muted,
    Color? led,
    Color? onLed,
    Color? power,
    Color? ok,
    Color? sheet,
    Color? okKey,
  }) => RemotePalette(
    body: body ?? this.body,
    key: key ?? this.key,
    keyPressed: keyPressed ?? this.keyPressed,
    keyEdge: keyEdge ?? this.keyEdge,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    led: led ?? this.led,
    onLed: onLed ?? this.onLed,
    power: power ?? this.power,
    ok: ok ?? this.ok,
    sheet: sheet ?? this.sheet,
    okKey: okKey ?? this.okKey,
  );

  @override
  RemotePalette lerp(RemotePalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return RemotePalette(
      body: c(body, other.body),
      key: c(key, other.key),
      keyPressed: c(keyPressed, other.keyPressed),
      keyEdge: c(keyEdge, other.keyEdge),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      led: c(led, other.led),
      onLed: c(onLed, other.onLed),
      power: c(power, other.power),
      ok: c(ok, other.ok),
      sheet: c(sheet, other.sheet),
      okKey: c(okKey, other.okKey),
    );
  }
}

extension RemotePaletteContext on BuildContext {
  RemotePalette get palette => Theme.of(this).extension<RemotePalette>() ?? RemotePalette.dark;
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? RemotePalette.dark : RemotePalette.light;
  final scheme = ColorScheme.fromSeed(seedColor: p.led, brightness: brightness).copyWith(
    surface: p.body,
    onSurface: p.text,
    primary: p.led,
    onPrimary: p.onLed,
    surfaceContainerHigh: p.key,
    surfaceContainerHighest: p.keyPressed,
    error: p.power,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.body,
    appBarTheme: AppBarTheme(
      backgroundColor: p.body,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: p.led, foregroundColor: p.onLed),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.sheet, showDragHandle: true),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onLed : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.led : p.keyEdge),
    ),
    textTheme: TextTheme(
      titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2, color: p.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: p.text),
      bodyMedium: TextStyle(color: p.text, height: 1.4),
      bodySmall: TextStyle(color: p.muted, height: 1.4),
      labelLarge: const TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}
