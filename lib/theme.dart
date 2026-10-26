import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFFF1EFF7);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1B1830);
  static const sub = Color(0xFF6F6A86);
  static const pri = Color(0xFF5236D9);
  static const live = Color(0xFFC4267F);
  static const line = Color(0xFFD8D4E6);
  static const dim = Color(0xFFE6E3F0);
}

class AppText {
  static const title = TextStyle(
    fontSize: 31,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );
  static const h2 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const body = TextStyle(fontSize: 14, color: AppColors.ink);
  static const small = TextStyle(fontSize: 12, color: AppColors.sub, height: 1.4);
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Courier'],
    fontSize: 10,
    color: AppColors.sub,
    letterSpacing: 0.5,
  );
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.pri),
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: Typography.blackMountainView.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
  );
}
