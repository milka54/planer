import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/update_service.dart';
import '../data/auth_service.dart';
import '../data/backup_service.dart';
import '../data/notes_repository.dart';
import '../data/storage.dart';
import 'auth_hub.dart';
import 'change_password_screen.dart';
import 'home_shell.dart';
import 'widgets.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  UpdateInfo? _update;
  bool _checkingUpdate = false;
  bool _downloading = false;
  double? _updateProgress;

  @override
  void initState() {
    super.initState();
    if (UpdateService.supportedOnThisPlatform) {
      _checkUpdate();
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    try {
      showSnack(context, 'Готовим резервную копию…');
      final path = await BackupService.instance.exportAll();
      if (!context.mounted) return;
      if (path == null) return;
      showSnack(context, 'Резервная копия сохранена');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Не удалось сохранить копию');
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Импорт данных'),
        content: const Text(
          'Заметки и напоминания из файла объединятся с текущими. '
          'По совпадению id побеждает более свежая версия.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выбрать файл'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final summary = await BackupService.instance.importAll();
      if (!context.mounted) return;
      if (summary == null) return;
      showSnack(
        context,
        'Импорт готов: ${summary.notes} заметок, ${summary.reminders} напоминаний',
      );
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Не удалось импортировать файл');
      }
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final info = await UpdateService.check();
    if (mounted) {
      setState(() {
        _update = info;
        _checkingUpdate = false;
      });
      if (info == null) {
        showSnack(context, 'У вас последняя версия');
      }
    }
  }

  Future<void> _runUpdate() async {
    final info = _update;
    if (info == null || _downloading) return;
    setState(() {
      _downloading = true;
      _updateProgress = null;
    });
    try {
      await UpdateService.download(
        info,
        onProgress: (p) {
          if (mounted) setState(() => _updateProgress = p);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        showSnack(context, 'Не удалось скачать обновление');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = AuthService.instance.isGuest.value;
    final email = AuthService.instance.userEmail.value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        Text(
          'Настройки',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppPalette.accent.withOpacity(0.25),
                child: Icon(
                  isGuest ? Icons.person_outline : Icons.cloud_done_rounded,
                  color: AppPalette.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGuest ? 'Гость' : (email ?? 'Аккаунт'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isGuest
                          ? 'Данные только на этом устройстве'
                          : 'Синхронизация с облаком включена',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionTitle('ВНЕШНИЙ ВИД'),
        GlassPanel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.brightness_6_rounded,
                title: 'Оформление',
                subtitle: '${curTheme.name} · ${curTheme.subtitle}',
                onTap: () => _pickTheme(context),
              ),
              const Divider(height: 8),
              _SettingsTile(
                icon: Icons.wallpaper_outlined,
                title: 'Фон приложения',
                subtitle: _bgLabel(),
                onTap: () => _pickBg(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionTitle('АККАУНТ'),
        GlassPanel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              if (isGuest)
                _SettingsTile(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Войти / регистрация',
                  subtitle: 'Перенести заметки в облако',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthHubScreen()),
                    );
                  },
                )
              else ...[
                _SettingsTile(
                  icon: Icons.sync_rounded,
                  title: 'Синхронизировать сейчас',
                  onTap: () async {
                    await NotesRepository.instance.load();
                    if (context.mounted) {
                      showSnack(context, 'Синхронизация выполнена');
                    }
                  },
                ),
                const Divider(height: 8),
                _SettingsTile(
                  icon: Icons.lock_reset_rounded,
                  title: 'Изменить пароль',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
              ],
              if (!isGuest) ...[
                const Divider(height: 8),
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Выйти из аккаунта',
                  onTap: () => logoutFlow(context),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SizedBox(height: 18),
        const SectionTitle('ДАННЫЕ'),
        GlassPanel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.save_alt_rounded,
                title: 'Экспорт данных',
                subtitle: 'Резервная копия: заметки, напоминания, вложения',
                onTap: () => _exportBackup(context),
              ),
              const Divider(height: 8),
              _SettingsTile(
                icon: Icons.restore_rounded,
                title: 'Импорт данных',
                subtitle: 'Восстановить из файла резервной копии',
                onTap: () => _importBackup(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionTitle('ПРИЛОЖЕНИЕ'),
        GlassPanel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.workspace_premium_outlined,
                title: 'Планер Premium',
                subtitle: 'BETA: сейчас бесплатно.\nСкоро регистрация станет платной.',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppPalette.accent.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppPalette.accent.withOpacity(0.45),
                    ),
                  ),
                  child: const Text(
                    'BETA',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                onTap: () {
                  showSnack(
                    context,
                    'Режим тестирования. Платная регистрация — в ближайшее время.',
                  );
                },
              ),
              const Divider(height: 8),
              // Проверка обновлений ПК-версии (только на Windows).
              if (UpdateService.supportedOnThisPlatform) ...[
                if (_update != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassPanel(
                      glow: true,
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppPalette.mint.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.system_update_rounded,
                              color: AppPalette.mint,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Доступно обновление ${_update!.version}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                if (_update!.notes.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _update!.notes,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: _downloading ? null : _runUpdate,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppPalette.mint,
                              foregroundColor: AppPalette.inkDeep,
                            ),
                            child: _downloading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: _updateProgress,
                                    ),
                                  )
                                : const Text('Обновить'),
                          ),
                        ],
                      ),
                    ),
                  ),
                _SettingsTile(
                  icon: Icons.system_update_rounded,
                  title: 'Проверить обновления',
                  subtitle: _checkingUpdate
                      ? 'Проверяем…'
                      : _update != null
                          ? 'Новая версия: ${_update!.version}'
                          : 'Текущая версия: ${UpdateService.appVersion}',
                  trailing: const Icon(Icons.refresh_rounded, size: 18),
                  onTap: () {
                    if (!_checkingUpdate) _checkUpdate();
                  },
                ),
                const Divider(height: 8),
              ],
              if (Platform.isWindows)
                _SettingsTile(
                  icon: Icons.phone_android_rounded,
                  title: 'Версия для смартфона',
                  subtitle: 'Установите Планер на смартфон —\nзаметки синхронизируются с компьютером',
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _showPhoneVersionDialog(context),
                )
              else
                _SettingsTile(
                  icon: Icons.computer_rounded,
                  title: 'Версия для ПК',
                  subtitle: 'Установите Планер на компьютер —\nзаметки синхронизируются с телефоном',
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _showPCVersionDialog(context),
                ),
              const Divider(height: 8),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'О приложении',
                subtitle: 'Планер 1.3.6',
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Планер',
                    applicationVersion: '1.3.6 · BETA',
                    children: const [
                      SizedBox(height: 12),
                      Text(
                        'Заметки с напоминаниями. Local-first: '
                        'сначала устройство, потом облако.',
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Приложение в режиме тестирования. '
                        'В скором времени регистрация станет платной.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _bgLabel() {
    if (curBg.id == 'gallery') {
      final p = StorageService.instance.customBgPath;
      return p == null ? 'Моё фото (не выбрано)' : 'Моё фото';
    }
    return curBg.name;
  }

  /// Ссылка на страницу смартфон-версии (RuStore).
  static const phoneVersionUrl =
      'https://www.rustore.ru/catalog/app/ru.planer.notes';

  /// Прямая ссылка на установщик ПК-версии (GitHub Releases).
  static const pcVersionUrl =
      'https://github.com/milka54/planer/releases/latest/download/planer-setup.exe';


  Future<void> _showPhoneVersionDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Планер для смартфона'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Мобильная версия позволяет работать с заметками '
              'на смартфоне: вход в тот же аккаунт, все разделы '
              'и заметки синхронизируются с компьютером.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.phone_android_rounded,
                    size: 18, color: AppPalette.accent),
                SizedBox(width: 8),
                Expanded(child: Text('Установите Планер из RuStore')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sync_rounded, size: 18, color: AppPalette.accent),
                SizedBox(width: 8),
                Expanded(child: Text('Войдите в аккаунт — данные подтянутся')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Скопировать ссылку'),
            onPressed: () async {
              await Clipboard.setData(
                  const ClipboardData(text: phoneVersionUrl));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                showSnack(context, 'Ссылка скопирована');
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Открыть RuStore'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await launchUrl(
                  Uri.parse(phoneVersionUrl),
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {
                showSnack(context, 'Не удалось открыть ссылку');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showPCVersionDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Планер для компьютера'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Windows-версия позволяет работать с заметками '
              'на компьютере: вход в тот же аккаунт, все разделы '
              'и заметки синхронизируются с телефоном.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.computer_rounded,
                    size: 18, color: AppPalette.accent),
                SizedBox(width: 8),
                Expanded(child: Text('Установите Планер для Windows')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sync_rounded, size: 18, color: AppPalette.accent),
                SizedBox(width: 8),
                Expanded(child: Text('Войдите в аккаунт — данные подтянутся')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Скопировать ссылку'),
            onPressed: () async {
              await Clipboard.setData(
                  const ClipboardData(text: pcVersionUrl));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                showSnack(context, 'Ссылка скопирована');
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: const Text('Скачать для Windows'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await launchUrl(
                  Uri.parse(pcVersionUrl),
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {
                showSnack(context, 'Не удалось скачать файл');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Оформление',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    for (final t in ThemeOption.all)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ThemeTile(
                          option: t,
                          selected: curTheme.id == t.id,
                          onTap: () {
                            themeNotifier.value = t;
                            StorageService.instance.setThemeId(t.id);
                            Navigator.pop(ctx);
                            setState(() {});
                          },
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

  Future<void> _pickGalleryImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2160,
      imageQuality: 88,
    );
    if (file == null) return;
    // Копируем в постоянное хранилище — временный путь image_picker пропадает.
    final persisted =
        await StorageService.instance.persistBackgroundImage(File(file.path));
    final path = persisted ?? file.path;
    await StorageService.instance.setCustomBgPath(path);
    await StorageService.instance.setBgId('gallery');
    // applyBg всегда оповещает: иначе повторный выбор фото при активной
    // «Галерее» не перерисует фон до перезапуска.
    applyBg(BgOption.gallery, customPath: path);
    if (mounted) setState(() {});
  }

  Future<void> _pickBg(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Фон приложения',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: BgOption.all.length,
                  itemBuilder: (context, i) {
                    final b = BgOption.all[i];
                    return _BgTile(
                      option: b,
                      selected: curBg.id == b.id,
                      customPath: StorageService.instance.customBgPath,
                      onTap: () async {
                        if (b.id == 'gallery') {
                          Navigator.pop(ctx);
                          await _pickGalleryImage();
                          return;
                        }
                        applyBg(
                          b,
                          customPath: StorageService.instance.customBgPath,
                        );
                        await StorageService.instance.setBgId(b.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : AppPalette.inkDeep;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: fg.withOpacity(0.85)),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15.5,
            color: fg,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  color: fg.withOpacity(0.72),
                ),
              ),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final ThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final previewBg = option.isDark ? AppPalette.inkDeep : AppPalette.paper;
    final previewCard =
        option.isDark ? const Color(0xFF1E2F52) : AppPalette.paperCard;

    return Material(
      color: previewBg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppPalette.accent : Colors.black12,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // мини-превью интерфейса
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: previewCard,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 8,
                      decoration: BoxDecoration(
                        color: option.accent.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 28,
                      height: 6,
                      decoration: BoxDecoration(
                        color: option.isDark
                            ? Colors.white24
                            : Colors.black12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(
                      option.isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 18,
                      color: option.accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color:
                            option.isDark ? Colors.white : AppPalette.inkDeep,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: (option.isDark
                                ? Colors.white
                                : AppPalette.inkDeep)
                            .withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: AppPalette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _BgTile extends StatelessWidget {
  final BgOption option;
  final bool selected;
  final String? customPath;
  final VoidCallback onTap;

  const _BgTile({
    required this.option,
    required this.selected,
    required this.customPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (option.id == 'none') {
      image = Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Center(
          child: Icon(Icons.format_color_fill_rounded, size: 36),
        ),
      );
    } else if (option.id == 'gallery') {
      image = customPath == null
          ? Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Center(
                child: Icon(Icons.add_photo_alternate_outlined, size: 36),
              ),
            )
          : Image.file(
              File(customPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            );
    } else if (option.isGradient) {
      image = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: option.gradientColors!,
          ),
        ),
      );
    } else {
      image = Image.asset(
        option.assetPath!,
        fit: BoxFit.cover,
        errorBuilder: (_, e, ___) {
          debugPrint('tile asset: ${option.assetPath} $e');
          return Container(color: Colors.black12);
        },
      );
    }

    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            // затемнение снизу под подпись
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.55),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppPalette.accent,
                  child: Icon(Icons.check, size: 18, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
