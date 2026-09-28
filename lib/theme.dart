import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFFEFEFEF);
  static const ink = Color(0xFF1A1A1A);
  static const ink2 = Color(0xFF555555);
  static const muted = Color(0xFF8A8A8A);
  static const faint = Color(0xFFC9C9C9);
  static const line = Color(0xFFE6E6E6);
  static const soft = Color(0xFFF2F2F2);
  static const soft2 = Color(0xFFFAFAFA);
  static const track = Color(0xFFE4E4E4);
  static const blue = Color(0xFF3B93F0);
  static const blueDeep = Color(0xFF1F7AE0);
  static const sky = Color(0xFF4DA3F5);
  static const skyTint = Color(0xFFE6F1FB);
  static const skyInk = Color(0xFF1F5F9E);
  static const green = Color(0xFF3D9148);
  static const greenTint = Color(0xFFE8F4EA);
  static const greenInk = Color(0xFF2F7D3C);
  static const amber = Color(0xFFE0A53A);
  static const amberTint = Color(0xFFFFF3DF);
  static const amberInk = Color(0xFFB86E00);
  static const red = Color(0xFFD0484E);
  static const redTint = Color(0xFFFDECEC);
  static const redInk = Color(0xFFC23B41);
  static const purple = Color(0xFF8A63C9);
  static const purpleTint = Color(0xFFF1ECF9);
  static const purpleInk = Color(0xFF6A45A8);
}

const partyColors = [C.sky, C.purple, Color(0xFF2FA39A), C.green, C.red, Color(0xFF6B6461)];

/// (strong, tint) pairs, picked deterministically per category name so a category
/// synced from the backoffice always gets the same color without a hand-written map.
const _catPalette = <(Color, Color)>[
  (Color(0xFFC2562B), Color(0xFFFBECE5)),
  (Color(0xFF6B6461), Color(0xFFF1EFEE)),
  (Color(0xFF3D9148), Color(0xFFE8F4EA)),
  (Color(0xFFE0A53A), Color(0xFFFCF3E2)),
  (Color(0xFF3F8FD6), Color(0xFFE6F1FB)),
  (Color(0xFFD0484E), Color(0xFFFBE9EA)),
  (Color(0xFF8A63C9), Color(0xFFF1ECF9)),
  (Color(0xFF2FA39A), Color(0xFFE3F4F3)),
];

(Color, Color) colorForCategory(String cat) => _catPalette[cat.hashCode.abs() % _catPalette.length];

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.blue, surface: Colors.white),
    scaffoldBackgroundColor: C.bg,
  );
  OutlineInputBorder b(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    dividerColor: C.line,
    dividerTheme: const DividerThemeData(color: C.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      hintStyle: const TextStyle(color: Color(0xFF9A9A9A)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: b(C.line),
      enabledBorder: b(C.line),
      focusedBorder: b(C.blue, 2),
    ),
  );
}
