import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/storage.dart';
import 'auth_hub.dart';
import 'home_shell.dart';
import 'widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.edit_note_rounded,
      title: 'Планер',
      subtitle: 'Заметки, которые не теряются.\nКрасиво. Быстро. По-вашему.',
    ),
    (
      icon: Icons.alarm_on_rounded,
      title: 'Напоминания',
      subtitle: 'Каждая мысль может вернуться\nв нужный момент.',
    ),
    (
      icon: Icons.cloud_sync_rounded,
      title: 'Гость или облако',
      subtitle: 'Начните без регистрации\nи синхронизируйте позже.',
    ),
  ];

  Future<void> _finish() async {
    await StorageService.instance.setOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthHubScreen()),
    );
  }

  Future<void> _guest() async {
    await StorageService.instance.setOnboardingDone();
    await AuthService.instance.continueAsGuest();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ThemedBackground(
        assetPath: ThemeOption.night.backgroundAsset,
        dim: true,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Пропустить'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: BetaBanner(compact: true),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              color: AppPalette.accent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: AppPalette.accent.withOpacity(0.35),
                              ),
                            ),
                            child: Icon(p.icon, size: 52, color: AppPalette.accent),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            p.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            p.subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.45,
                              color: Colors.white.withOpacity(0.78),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? AppPalette.accent : Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Column(
                  children: [
                    PrimaryButton(
                      label: _page == _pages.length - 1
                          ? 'Продолжить'
                          : 'Дальше',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () {
                        if (_page == _pages.length - 1) {
                          _finish();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _guest,
                      child: Text(
                        'Продолжить как гость',
                        style: TextStyle(color: Colors.white.withOpacity(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
