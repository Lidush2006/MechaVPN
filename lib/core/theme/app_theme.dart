import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

/// NYX theme: always dark, built from the exact colors of the design spec.
class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  // ── NYX palette ──
  static const _bg = Color(0xFF0B0B0E);
  static const _panel = Color(0xFF15151A);
  static const _panel2 = Color(0xFF1C1C22);
  static const _border = Color(0xFF2A2A30);
  static const _red = Color(0xFFE10600);
  static const _redBright = Color(0xFFFF2A1A);
  static const _brass = Color(0xFFC8962E);
  static const _cyan = Color(0xFF00E5FF);
  static const _text = Color(0xFFE8E8EC);
  static const _muted = Color(0xFF8A8A92);

  static const ColorScheme nyxScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _redBright,
    onPrimary: Color(0xFF1A0200),
    primaryContainer: Color(0xFF3A0A08),
    onPrimaryContainer: Color(0xFFFFD9D4),
    secondary: _brass,
    onSecondary: Color(0xFF1A1200),
    secondaryContainer: Color(0xFF3A2C0A),
    onSecondaryContainer: Color(0xFFFFE9B8),
    tertiary: _cyan,
    onTertiary: Color(0xFF00171A),
    error: _red,
    onError: Colors.white,
    surface: _bg,
    onSurface: _text,
    onSurfaceVariant: _muted,
    outline: Color(0xFF3A3A44),
    outlineVariant: _border,
    surfaceContainerLowest: _bg,
    surfaceContainerLow: _panel,
    surfaceContainer: _panel,
    surfaceContainerHigh: _panel2,
    surfaceContainerHighest: _panel2,
  );

  ThemeData _nyxTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: nyxScheme,
      scaffoldBackgroundColor: _bg,
      dividerTheme: const DividerThemeData(color: _border),
      // the font is bundled in assets/fonts (see pubspec.yaml), so it works without internet
      fontFamily: 'Exo2',
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  // The app is always dark: both modes give the same NYX theme.
  ThemeData lightTheme(ColorScheme? lightColorScheme) => _nyxTheme();

  ThemeData darkTheme(ColorScheme? darkColorScheme) => _nyxTheme();

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    const def = CupertinoThemeData(brightness: Brightness.dark);

    final defaultMaterialTheme = darkTheme(darkColorScheme);
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: _bg,
        ),
      ),
    );
  }
}
