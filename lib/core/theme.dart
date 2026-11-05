import 'package:flutter/material.dart';

class AppPalette {
  /// Активная тема — источник акцентных цветов. Меняется в
  /// buildTheme() — каждая смена оформления проходит через неё.
  static ThemeOption _active = ThemeOption.night;

  static void activate(ThemeOption option) => _active = option;

  static Color get accent => _active.accent;
  static Color get accentSoft => _active.accentSoft;

  static const ink = Color(0xFF1B2A4A);
  static const inkDeep = Color(0xFF121C33);
  static const paper = Color(0xFFF7F3EC);
  static const paperCard = Color(0xFFFFFCF7);
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
    Color(0xFFE07A5F),
    Color(0xFF3D5A80),
    Color(0xFF98C1D9),
    Color(0xFFEE6C4D),
    Color(0xFF293241),
  ];
}

/// Тема = цвета интерфейса (светлая/тёмная).
class ThemeOption {
  final String id;
  final String name;
  final String subtitle;
  final bool isDark;
  final Color seed;

  /// Фирменные цвета темы: яркий акцент и его светлая вариация.
  /// Видны везде: FAB, кнопки, иконки, индикаторы.
  final Color accent;
  final Color accentSoft;
  final String? backgroundAsset;

  const ThemeOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.isDark,
    required this.seed,
    required this.accent,
    required this.accentSoft,
    this.backgroundAsset,
  });

  static const night = ThemeOption(
    id: 'night',
    name: 'Ночь',
    subtitle: 'Тёмная, для вечера',
    isDark: true,
    seed: AppPalette.sky,
    accent: const Color(0xFFE8A54B),
    accentSoft: const Color(0xFFF3C77B),
    backgroundAsset: 'assets/backgrounds/bg_night.png',
  );

  static const day = ThemeOption(
    id: 'day',
    name: 'День',
    subtitle: 'Светлая и спокойная',
    isDark: false,
    seed: AppPalette.ink,
    accent: const Color(0xFF3A6EA5),
    accentSoft: const Color(0xFF5A8FC4),
    backgroundAsset: 'assets/backgrounds/bg_classic.png',
  );

  static const graphite = ThemeOption(
    id: 'graphite',
    name: 'Графит',
    subtitle: 'Строгая тёмная',
    isDark: true,
    seed: Color(0xFF6B7280),
    accent: const Color(0xFF9AA5B1),
    accentSoft: const Color(0xFFC3CCD6),
    backgroundAsset: 'assets/backgrounds/bg_business.png',
  );

  static const cream = ThemeOption(
    id: 'cream',
    name: 'Крем',
    subtitle: 'Тёплая светлая',
    isDark: false,
    seed: Color(0xFFB8956A),
    accent: const Color(0xFFB8713E),
    accentSoft: const Color(0xFFA0703C),
    backgroundAsset: 'assets/backgrounds/bg_sunset.png',
  );

  static const lavender = ThemeOption(
    id: 'lavender',
    name: 'Лаванда',
    subtitle: 'Сиреневая, мягкая',
    isDark: true,
    seed: Color(0xFF9B8AE0),
    accent: const Color(0xFF9B8AE0),
    accentSoft: const Color(0xFFBCA9F5),
  );

  static const ocean = ThemeOption(
    id: 'ocean',
    name: 'Океан',
    subtitle: 'Глубокая бирюза',
    isDark: true,
    seed: Color(0xFF2EC4B6),
    accent: const Color(0xFF2EC4B6),
    accentSoft: const Color(0xFF6FDCD0),
  );

  static const forest = ThemeOption(
    id: 'forest',
    name: 'Лес',
    subtitle: 'Спокойная зелёная',
    isDark: true,
    seed: Color(0xFF52B788),
    accent: const Color(0xFF52B788),
    accentSoft: const Color(0xFF86D3AC),
  );

  static const rose = ThemeOption(
    id: 'rose',
    name: 'Роза',
    subtitle: 'Нежная светлая',
    isDark: false,
    seed: Color(0xFFE8889B),
    accent: const Color(0xFFE06B84),
    accentSoft: const Color(0xFFC4667E),
  );

  static const sunset = ThemeOption(
    id: 'sunset',
    name: 'Закат',
    subtitle: 'Тёплый оранжевый',
    isDark: false,
    seed: Color(0xFFF4845F),
    accent: const Color(0xFFF4724B),
    accentSoft: const Color(0xFFC85A32),
  );

  static const midnight = ThemeOption(
    id: 'midnight',
    name: 'Полночь',
    subtitle: 'Глубокий индиго',
    isDark: true,
    seed: Color(0xFF5B6CFF),
    accent: const Color(0xFF6C7CFF),
    accentSoft: const Color(0xFF9BA7FF),
  );

  static const all = [
    night,
    day,
    graphite,
    cream,
    lavender,
    ocean,
    forest,
    rose,
    sunset,
    midnight,
  ];

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

  /// Градиентная заливка (когда нет картинки).
  final List<Color>? gradientColors;

  const BgOption({
    required this.id,
    required this.name,
    this.assetPath,
    this.isCustom = false,
    this.gradientColors,
  });

  bool get isGradient =>
      gradientColors != null && gradientColors!.length >= 2;

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

  // ── Градиенты ────────────────────────────────────────────────

  static const gradSunset = BgOption(
    id: 'grad_sunset',
    name: 'Градиент «Закат»',
    gradientColors: [Color(0xFFFF9A5A), Color(0xFFFF5E62), Color(0xFF8A2387)],
  );

  static const gradOcean = BgOption(
    id: 'grad_ocean',
    name: 'Градиент «Океан»',
    gradientColors: [Color(0xFF2E3192), Color(0xFF1BFFFF), Color(0xFF48C6EF)],
  );

  static const gradLavender = BgOption(
    id: 'grad_lavender',
    name: 'Градиент «Лаванда»',
    gradientColors: [Color(0xFF8E2DE2), Color(0xFFDA22FF), Color(0xFFFFC8DD)],
  );

  static const gradForest = BgOption(
    id: 'grad_forest',
    name: 'Градиент «Лес»',
    gradientColors: [Color(0xFF134E5E), Color(0xFF71B280), Color(0xFFD7F5E2)],
  );

  static const gradRose = BgOption(
    id: 'grad_rose',
    name: 'Градиент «Роза»',
    gradientColors: [Color(0xFFFFAFBD), Color(0xFFFFC3A0), Color(0xFFFFE29F)],
  );

  static const gradMidnight = BgOption(
    id: 'grad_midnight',
    name: 'Градиент «Полночь»',
    gradientColors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
  );

  static const gradMint = BgOption(
    id: 'grad_mint',
    name: 'Градиент «Мята»',
    gradientColors: [Color(0xFF93F9B9), Color(0xFF1D976C), Color(0xFF0B6E4F)],
  );

  static const gradMono = BgOption(
    id: 'grad_mono',
    name: 'Градиент «Моно»',
    gradientColors: [Color(0xFF232526), Color(0xFF414345), Color(0xFF6E6E6E)],
  );

  static const gradPeach = BgOption(
    id: 'grad_peach',
    name: 'Градиент «Персик»',
    gradientColors: [Color(0xFFFFECD2), Color(0xFFFCB69F), Color(0xFFFF8177)],
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
    gradSunset,
    gradOcean,
    gradLavender,
    gradForest,
    gradRose,
    gradMidnight,
    gradMint,
    gradMono,
    gradPeach,
    gallery,
  ];

  static BgOption byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return none;
  }

  String? resolve({String? customPath}) {
    if (id == 'none' || isGradient) return null;
    if (id == 'gallery') return customPath;
    return assetPath;
  }
}

ThemeData buildTheme(ThemeOption option) {
  // Палитра AppPalette следует за темой: акцентные цвета меняются
  // вместе с оформлением в настройках.
  AppPalette.activate(option);
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
      foregroundColor: scheme.onPrimary,
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
