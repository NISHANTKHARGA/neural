import 'package:flutter/material.dart';

/// SAFETRAILS palette — crimson and white.
///
/// Crimson is the action colour; white carries the surfaces. The accents
/// (gold, green, blue) are darkened to 700-weight shades because the previous
/// values were tuned for a dark background and lost contrast on white.
///
/// `snow` and `muted` are used exclusively as text/foreground colours, so they
/// hold dark ink here rather than white.
class Nepali {
  Nepali._();

  static const night = Color(0xFFFFFFFF);
  static const nightDeep = Color(0xFFFFF4F6);
  static const panel = Color(0xFFFFFFFF);
  static const panelLight = Color(0xFFFFF3F5);
  static const line = Color(0xFFF2C6CD);

  static const crimson = Color(0xFFDC143C);
  static const crimsonDark = Color(0xFFA80F2F);
  static const crimsonSoft = Color(0x1ADC143C);

  static const royal = Color(0xFF1D4ED8);
  static const gold = Color(0xFFB45309);
  static const snow = Color(0xFF1B1013);
  static const muted = Color(0xFF7A5C63);

  static const risk0 = Color(0xFFDC143C); // SOS level
  static const risk1 = Color(0xFFB45309); // rescue/latest
  static const risk2 = Color(0xFF1D4ED8); // informational

  static const green = Color(0xFF15803D);

  // Formerly the Nepal flag palette, used for decorative prayer-flag and
  // floral swatches. Both are gone; kept only so an in-flight branch that
  // still references them fails to compile rather than silently changing a
  // colour. Safe to delete once no branch references them.
  static const prayerBlue = Color(0xFF3B82F6);
  static const prayerWhite = Color(0xFFF5F7FA);
  static const prayerRed = Color(0xFFDC143C);
  static const prayerGreen = Color(0xFF2FA96B);
  static const prayerGold = Color(0xFFFFC857);
}