import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme.dart';
import 'data/auth_service.dart';
import 'data/notifications.dart';
import 'data/notes_repository.dart';
import 'data/reminder_service.dart';
import 'data/storage.dart';
import 'ui/auth_hub.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await StorageService.instance.init();
  await NotificationService.instance.init();

  try {
    await Firebase.initializeApp();
    AuthService.instance.cloudReady = true;
  } catch (e) {
    AuthService.instance.cloudReady = false;
    debugPrint('Firebase init failed (local mode): $e');
  }

  await AuthService.instance.init();
  await ReminderService.instance.load();

  themeNotifier.value = ThemeOption.byId(StorageService.instance.themeId);
  applyBg(
    BgOption.byId(StorageService.instance.bgId),
    customPath: StorageService.instance.customBgPath,
  );

  // Если кастомный фон пропал — откатываемся на «Бумагу» сразу.
  final customPath = StorageService.instance.customBgPath;
  if (bgNotifier.value.option.id == 'gallery' &&
      (customPath == null || !File(customPath).existsSync())) {
    applyBg(BgOption.classic);
    await StorageService.instance.setBgId('classic');
    await StorageService.instance.clearCustomBgPath();
  }

  runApp(const PlanerApp());
}

class PlanerApp extends StatelessWidget {
  const PlanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeOption>(
      valueListenable: themeNotifier,
      builder: (context, theme, _) {
        return ValueListenableBuilder<BgState>(
          valueListenable: bgNotifier,
          builder: (context, bg, _) {
            final bgOpt = bg.option;
            final custom = bg.customPath;
            final customOk = custom != null && File(custom).existsSync();
            final asset = bgOpt.resolve(
              customPath: customOk ? custom : null,
            );
            final isFile = bgOpt.id == 'gallery' && customOk && asset != null;
            // Если галерея выбрана, но файла нет — градиент/бумага.
            final fallbackAsset =
                (bgOpt.id == 'gallery' && !isFile) ? null : asset;
            return MaterialApp(
              title: 'Планер',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(theme),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ru', 'RU')],
              locale: const Locale('ru', 'RU'),
              home: Builder(
                builder: (context) {
                  return ThemedBackground(
                    key: ValueKey('${theme.id}_${bgOpt.id}_$asset'),
                    assetPath: isFile ? null : fallbackAsset,
                    filePath: isFile ? asset : null,
                    dim: true,
                    child: const _RootGate(),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _boot();
  }

  Future<void> _boot() async {
    await NotesRepository.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!StorageService.instance.onboardingDone) {
          return const OnboardingScreen();
        }

        if (AuthService.instance.isGuest.value) {
          return const HomeShell();
        }

        return const HomeShell();
      },
    );
  }
}

/// Экран выбора режима (используется после logout).
class ModePickerScreen extends StatelessWidget {
  const ModePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Планер',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Выберите режим работы',
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Войти в облако',
                icon: Icons.cloud_rounded,
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthHubScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await AuthService.instance.continueAsGuest();
                  await NotesRepository.instance.load();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeShell()),
                    (route) => false,
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('Продолжить как гость'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
