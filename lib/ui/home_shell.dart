import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/family_service.dart';
import '../data/notes_repository.dart';
import 'auth_hub.dart';
import 'join_space_screen.dart';
import 'note_editor.dart';
import 'family_tab.dart';
import 'notes_tab.dart';
import 'reminders_tab.dart';
import 'settings_tab.dart';

/// Состояние фона: выбранный вариант + путь кастомного изображения.
/// Это запись (record), а не BgOption: смена пути при том же варианте
/// обязана оповещать слушателей, иначе фон обновится только после перезапуска.
typedef BgState = ({BgOption option, String? customPath});

final themeNotifier = ValueNotifier<ThemeOption>(ThemeOption.night);
final bgNotifier = ValueNotifier<BgState>(
  (option: BgOption.classic, customPath: null),
);

ThemeOption get curTheme => themeNotifier.value;
BgOption get curBg => bgNotifier.value.option;

/// Применяет фон и всегда оповещает слушателей.
void applyBg(BgOption option, {String? customPath}) {
  bgNotifier.value = (option: option, customPath: customPath);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _pageCtrl = PageController();
  StreamSubscription<Uri>? _deepLinksSub;

  @override
  void initState() {
    super.initState();
    // Ссылка-приглашение planer://join/<token> — открываем экран вступления.
    _deepLinksSub = AppLinks().uriLinkStream.listen(_handleDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotesRepository.instance.load();
      FamilyService.instance.load().then((_) {
        FamilyService.instance.loadUnread();
        // Ловим сообщения, пока пользователь в любом разделе приложения.
        FamilyService.instance.startBackgroundPolling();
      });
    });
  }

  @override
  void dispose() {
    _deepLinksSub?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'planer' || uri.host != 'join') return;
    // Ждём построения дерева, чтобы navigator был доступен.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await showJoinSpaceScreen(
      context,
      initialCode: uri.toString(),
    );
    FamilyService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, a, __) => FadeTransition(
          opacity: a,
          child: const NoteEditorScreen(),
        ),
      ),
    );
    await NotesRepository.instance.load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: PageView(
          controller: _pageCtrl,
          onPageChanged: (i) => setState(() => _index = i),
          children: const [
            NotesTab(),
            RemindersTab(),
            FamilyTab(),
            SettingsTab(),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _index == 0
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              builder: (context, t, child) =>
                  Transform.scale(scale: t.clamp(0, 1.1), child: child),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'fab_section',
                      onPressed: () => showCreateSectionDialog(context),
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF2A3D66)
                              : Colors.white,
                      foregroundColor: AppPalette.accent,
                      elevation: 6,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text(
                        'Раздел',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    FloatingActionButton.extended(
                      heroTag: 'fab_note',
                      onPressed: _openEditor,
                      backgroundColor: AppPalette.accent,
                      foregroundColor: AppPalette.inkDeep,
                      elevation: 8,
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text(
                        'Новая',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      bottomNavigationBar: ValueListenableBuilder<Map<String, int>>(
        valueListenable: FamilyService.instance.unread,
        builder: (context, unreadMap, _) {
          final totalUnread =
              unreadMap.values.fold<int>(0, (a, b) => a + b);
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _goTo,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Заметки',
              ),
              const NavigationDestination(
                icon: Icon(Icons.alarm_rounded),
                selectedIcon: Icon(Icons.alarm_rounded),
                label: 'Напоминания',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: totalUnread > 0,
                  label: Text('$totalUnread'),
                  child: const Icon(Icons.groups_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: totalUnread > 0,
                  label: Text('$totalUnread'),
                  child: const Icon(Icons.groups_rounded),
                ),
                label: 'Общие',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Настройки',
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> logoutFlow(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Выйти из аккаунта?'),
      content: const Text(
        'Заметки останутся на устройстве. Вы сможете удалить их вручную.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Выйти'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await AuthService.instance.signOut();
  await NotesRepository.instance.load();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthHubScreen()),
    (route) => false,
  );
}

String ownerLabel() {
  if (AuthService.instance.isGuest.value) return 'Гостевой режим';
  return AuthService.instance.userEmail.value ?? 'Облачный аккаунт';
}
