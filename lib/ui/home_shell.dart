import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../core/update_service.dart';
import '../data/auth_service.dart';
import '../data/family_service.dart';
import '../data/notes_repository.dart';
import '../data/reminder_service.dart';
import '../data/notifications.dart';
import 'auth_hub.dart';
import 'family_space_screen.dart';
import 'join_space_screen.dart';
import 'note_detail.dart';
import 'multi_select_bar.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  final _pageCtrl = PageController();
  StreamSubscription<Uri>? _deepLinksSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Ссылка-приглашение planer://join/<token> — открываем экран вступления.
    _deepLinksSub = AppLinks().uriLinkStream.listen(_handleDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.onTap = _handleNotifTap;
      unawaited(SharedPreferences.getInstance()
          .then((p) => p.setBool('app_foreground_v1', true)));
      NotesRepository.instance.load();
      FamilyService.instance.load().then((_) {
        FamilyService.instance.loadUnread();
        // Ловим сообщения, пока пользователь в любом разделе приложения.
        FamilyService.instance.startBackgroundPolling();
        // Запуск по тапу на уведомление — открываем нужный раздел.
        final launch = NotificationService.consumeLaunchPayload();
        if (launch != null) _handleNotifTap(launch);
      });
      // ПК-версия: автообновление из приложения без установщика.
      if (UpdateService.supportedOnThisPlatform) {
        unawaited(_autoUpdate());
      }
    });
  }

  /// Обновление ПК-версии прямо из приложения: проверяет при старте и
  /// предлагает установить на месте (без установщика и переустановки).
  Future<void> _autoUpdate() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    final info = await UpdateService.check();
    if (info == null || !mounted) return;
    final install = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Доступно обновление ${info.version}'),
        content: Text(
          info.notes.isEmpty
              ? 'Установить обновление сейчас?'
              : '${info.notes}\n\nУстановить обновление сейчас?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Установить'),
          ),
        ],
      ),
    );
    if (install != true || !mounted) return;
    try {
      await UpdateService.download(info);
    } catch (_) {
      // Сбой не рвёт работу приложения — обновление повторится при следующем старте.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.onTap = null;
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

  /// Тап по уведомлению: открывает раздел, к которому оно относится.
  /// payload: 'note:<id>' | 'rem:<id>' | 'chat:<spaceId>' | 'task:<spaceId>'.
  Future<void> _handleNotifTap(String payload) async {
    final sep = payload.indexOf(':');
    if (sep <= 0) return;
    final kind = payload.substring(0, sep);
    final id = payload.substring(sep + 1);
    // Даём навигатору построиться (холодный старт).
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    switch (kind) {
      case 'chat' || 'task':
        var found =
            FamilyService.instance.spaces.value.where((s) => s.id == id);
        if (found.isEmpty) {
          await FamilyService.instance.load();
          found =
              FamilyService.instance.spaces.value.where((s) => s.id == id);
        }
        if (found.isEmpty || !mounted) return;
        _goTo(2);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FamilySpaceScreen(
              space: found.first,
              initialTab: kind == 'chat' ? 1 : 0,
            ),
          ),
        );
        if (mounted) setState(() {});
      case 'note':
        final notes = NotesRepository.instance.all.where((n) => n.id == id);
        if (notes.isEmpty) return;
        _goTo(0);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoteDetailScreen(note: notes.first),
          ),
        );
        if (mounted) setState(() {});
      case 'rem':
        _goTo(1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Флаг «на переднем плане» видят и поллер, и фоновая проверка:
    // подавлять уведомления открытого чата можно только пока пользователь
    // реально смотрит в экран, свёрнутое приложение обязано уведомлять.
    final fg = state == AppLifecycleState.resumed;
    FamilyService.appInForeground = fg;
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setBool('app_foreground_v1', fg)));
    if (state != AppLifecycleState.resumed) return;
    // Возврат в приложение: система могла убить процесс
    // (батарея TECNO и т.п.) — будильники пропадают, уведомления
    // чата/задач заминают. Догоняем оба.
    ReminderService.instance.load();
    FamilyService.instance.pollAllSpaces();
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
      // Пока идёт множественный выбор — FAB прячем: панель действий
      // (переместить/в архив/удалить) занимает нижнюю зону экрана.
      floatingActionButton: _index == 0
          ? ValueListenableBuilder<bool>(
              valueListenable: notesSelectActive,
              builder: (context, selecting, __) => selecting
                  ? const SizedBox.shrink()
                  : TweenAnimationBuilder<double>(
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
  await FamilyService.instance.clear();
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
