import 'package:flutter/material.dart';

class AppPalette {
  static const ink = Color(0xFF1B2A4A);
  static const inkDeep = Color(0xFF121C33);
  static const paper = Color(0xFFF7F3EC);
  static const paperCard = Color(0xFFFFFCF7);
  static const accent = Color(0xFFE8A54B);
  static const accentSoft = Color(0xFFF3C77B);
  static const mint = Color(0xFF5BB8A6);
  static const rose = Color(0xFFD97777);
  static const sky = Color(0xFF6B9FD4);
  static const violet = Color(0xFF8B7EC8);

  static const noteColors = [
    Color(0xFFE8A54B),
    Color(0xFF5BB8A6),
    Color(0xFF6B9FD4),
    Color(0xFFD97777),
    Color(0xFF8B7EC8),
    Color(0xFFB8956A),
    Color(0xFF7BAE7F),
  ];
}

/// Тема = цвета интерфейса (светлая/тёмная).
class ThemeOption {
  final String id;
  final String name;
  final String subtitle;
  final bool isDark;
  final Color seed;
  final String? backgroundAsset;

  const ThemeOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.isDark,
    required this.seed,
    this.backgroundAsset,
  });

  static const night = ThemeOption(
    id: 'night',
    name: 'Ночь',
    subtitle: 'Тёмная, для вечера',
    isDark: true,
    seed: AppPalette.sky,
    backgroundAsset: 'assets/backgrounds/bg_night.png',
  );

  static const day = ThemeOption(
    id: 'day',
    name: 'День',
    subtitle: 'Светлая и спокойная',
    isDark: false,
    seed: AppPalette.ink,
    backgroundAsset: 'assets/backgrounds/bg_classic.png',
  );

  static const graphite = ThemeOption(
    id: 'graphite',
    name: 'Графит',
    subtitle: 'Строгая тёмная',
    isDark: true,
    seed: const Color(0xFF6B7280),
    backgroundAsset: 'assets/backgrounds/bg_business.png',
  );

  static const cream = ThemeOption(
    id: 'cream',
    name: 'Крем',
    subtitle: 'Тёплая светлая',
    isDark: false,
    seed: const Color(0xFFB8956A),
    backgroundAsset: 'assets/backgrounds/bg_sunset.png',
  );

  static const all = [night, day, graphite, cream];

  static ThemeOption byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return night;
  }
}

/// Фон = «обои» приложения.
class BgOption {
  final String id;
  final String name;
  final String? assetPath;
  final bool isCustom;

  const BgOption({
    required this.id,
    required this.name,
    this.assetPath,
    this.isCustom = false,
  });

  /// Сплошной цвет темы — без картинки.
  static const none = BgOption(id: 'none', name: 'Сплошной цвет');

  static const night = BgOption(
    id: 'night',
    name: 'Ночное небо',
    assetPath: 'assets/backgrounds/bg_night.png',
  );

  static const classic = BgOption(
    id: 'classic',
    name: 'Бумага',
    assetPath: 'assets/backgrounds/bg_classic.png',
  );

  static const business = BgOption(
    id: 'business',
    name: 'Деловой',
    assetPath: 'assets/backgrounds/bg_business.png',
  );

  static const nature = BgOption(
    id: 'nature',
    name: 'Природа',
    assetPath: 'assets/backgrounds/bg_nature.png',
  );

  static const sunset = BgOption(
    id: 'sunset',
    name: 'Закат',
    assetPath: 'assets/backgrounds/bg_sunset.png',
  );

  static const gallery = BgOption(
    id: 'gallery',
    name: 'Моё фото',
    isCustom: true,
  );

  static const all = [
    none,
    night,
    classic,
    business,
    nature,
    sunset,
    gallery,
  ];

  static BgOption byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return none;
  }

  String? resolve({String? customPath}) {
    if (id == 'none') return null;
    if (id == 'gallery') return customPath;
    return assetPath;
  }
}

ThemeData buildTheme(ThemeOption option) {
  final scheme = ColorScheme.fromSeed(
    seedColor: option.seed,
    brightness: option.isDark ? Brightness.dark : Brightness.light,
  );

  final bg = option.isDark ? AppPalette.inkDeep : AppPalette.paper;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: option.isDark ? Colors.white : AppPalette.inkDeep,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: option.isDark ? Colors.white : AppPalette.inkDeep,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: option.isDark ? const Color(0xFF1E2F52) : AppPalette.paperCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppPalette.accent,
      foregroundColor: AppPalette.inkDeep,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: option.isDark
          ? const Color(0xFF243558)
          : Colors.white.withOpacity(0.85),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: option.isDark
          ? const Color(0xFF17233F).withOpacity(0.92)
          : Colors.white.withOpacity(0.92),
      indicatorColor: AppPalette.accent.withOpacity(0.28),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 68,
    ),
    dividerTheme: DividerThemeData(
      color: option.isDark ? Colors.white12 : Colors.black12,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          option.isDark ? AppPalette.ink : AppPalette.inkDeep,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: ThemeData(
      brightness: option.isDark ? Brightness.dark : Brightness.light,
    ).textTheme.apply(
          bodyColor: option.isDark ? Colors.white : AppPalette.inkDeep,
          displayColor: option.isDark ? Colors.white : AppPalette.inkDeep,
        ),
  );
}
