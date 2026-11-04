import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/family_service.dart';
import '../data/models/family_space.dart';
import 'emoji_picker.dart';
import 'reminder_time_picker.dart';
import 'widgets.dart';

/// Экран пространства: задачи-чеклист + чат участников.
class FamilySpaceScreen extends StatefulWidget {
  const FamilySpaceScreen({
    super.key,
    required this.space,
    this.initialTab = 0,
  });

  final FamilySpace space;

  /// 0 — задачи, 1 — чат (из уведомления открываем нужную вкладку).
  final int initialTab;

  @override
  State<FamilySpaceScreen> createState() => _FamilySpaceScreenState();
}

class _FamilySpaceScreenState extends State<FamilySpaceScreen> {
  List<FamilyNote> _notes = [];
  List<FamilyMessage> _messages = [];
  List<FamilyMember> _members = [];
  bool _loading = true;
  int _tab = 0;
  final _msgCtrl = TextEditingController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    // Чат этого пространства открыт — фоновый опрос не уведомляет о нём.
    // Копия в prefs — её видит фоновая проверка (background_service.dart).
    FamilyService.activeChatSpaceId = widget.space.id;
    unawaited(SharedPreferences.getInstance().then(
        (p) => p.setString('active_chat_space_v1', widget.space.id)));
    FamilyService.instance.markRead(widget.space.id);
    _reload().then((_) {
      // Живые обновления чата, пока экран открыт.
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _pollMessages();
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (FamilyService.activeChatSpaceId == widget.space.id) {
      FamilyService.activeChatSpaceId = null;
      unawaited(SharedPreferences.getInstance()
          .then((p) => p.remove('active_chat_space_v1')));
    }
    _msgCtrl.dispose();
    super.dispose();
  }

  /// Подтягивает задачи и сообщения. Задачи обновляются ВСЕГДА —
  /// статусы «выполнено» и правки приходят от других участников.
  Future<void> _pollMessages() async {
    try {
      final deletions =
          await FamilyService.instance.reconcileDeletions(widget.space.id);
      final freshNotes = await FamilyService.instance.notes(widget.space.id);
      final fresh = await FamilyService.instance.messages(widget.space.id);
      if (!mounted) return;
      setState(() {
        _notes = freshNotes;
        _messages = fresh;
      });
      for (final d in deletions) {
        final name = d['deletedByName'] ?? 'Участник';
        final title = d['title'] ?? '';
        final wasDone = d['wasDone'] == true;
        if (mounted) {
          showSnack(
            context,
            '$name удалил(а) ${wasDone ? 'выполненную' : 'невыполненную'} '
            'задачу «$title»',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final id = widget.space.id;
    // Сначала сверяем удаления от других участников.
    final deletions = await FamilyService.instance.reconcileDeletions(id);
    final notes = await FamilyService.instance.notes(id);
    final msgs = await FamilyService.instance.messages(id);
    final members = await FamilyService.instance.members(id, force: true);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _messages = msgs;
      _members = members;
      _loading = false;
    });
    for (final d in deletions) {
      final name = d['deletedByName'] ?? 'Участник';
      final title = d['title'] ?? '';
      final wasDone = d['wasDone'] == true;
      if (mounted) {
        showSnack(
          context,
          '$name удалил(а) ${wasDone ? 'выполненную' : 'невыполненную'} '
          'задачу «$title»',
        );
      }
    }
  }

  /// Единая форма создания задачи: крупные поля, дата и время отдельными
  /// кнопками, окно не прячется за клавиатурой.
  Future<void> _addNote([FamilyNote? existing]) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl =
        TextEditingController(text: existing?.content ?? '');
    DateTime? when = existing?.reminderDate;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1E2F52),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          // Отступ от клавиатуры — текст не прячется за ней.
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'Новая задача' : 'Изменить задачу',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Заголовок',
                    hintText: 'Что нужно сделать',
                    suffixIcon: DictationSuffix(controller: titleCtrl),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: contentCtrl,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                  decoration: InputDecoration(
                    labelText: 'Описание',
                    hintText: 'Подробности, список покупок, адрес…',
                    suffixIcon: DictationSuffix(controller: contentCtrl),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _WhenButton(
                        icon: Icons.calendar_month_rounded,
                        label: 'Дата',
                        value: when == null
                            ? 'Не выбрана'
                            : MaterialLocalizations.of(ctx)
                                .formatCompactDate(when!),
                        selected: when != null,
                        onTap: () async {
                          final picked = await showReminderDateTimePicker(
                            context,
                            initial: when,
                          );
                          if (picked != null) {
                            setSheet(() => when = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WhenButton(
                        icon: Icons.schedule_rounded,
                        label: 'Время',
                        value: when == null
                            ? 'Не выбрано'
                            : TimeOfDay.fromDateTime(when!).format(context),
                        selected: when != null,
                        onTap: () async {
                          final picked = await showReminderDateTimePicker(
                            context,
                            initial: when,
                          );
                          if (picked != null) {
                            setSheet(() => when = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (when != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => when = null),
                      icon: const Icon(Icons.alarm_off_rounded, size: 18),
                      label: const Text('Убрать напоминание'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                    child: Text(
                      existing == null ? 'Создать' : 'Сохранить',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (created != true || !mounted) return;
    if (existing != null) {
      await FamilyService.instance.updateNote(
        widget.space.id,
        existing.copyWith(
          title: titleCtrl.text.trim(),
          content: contentCtrl.text.trim(),
          reminderDate: when,
          clearReminder: when == null,
        ),
      );
    } else {
      await FamilyService.instance.addNote(
        spaceId: widget.space.id,
        title: titleCtrl.text.trim(),
        content: contentCtrl.text.trim(),
        reminderDate: when,
      );
    }
    titleCtrl.dispose();
    contentCtrl.dispose();
    await _reload();
  }

  Future<void> _toggle(FamilyNote note) async {
    await FamilyService.instance.toggleDone(widget.space.id, note);
    await _reload();
  }

  Future<void> _deleteNote(FamilyNote note) async {
    // Для невыполненной задачи уточняем статус — иначе у других участников
    // непонятно, на каком этапе её удалили.
    var wasDone = note.done;
    if (!note.done) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Удалить задачу?'),
          content: Text(
            '«${note.title}»\n\n'
            'Задача не отмечена как выполненная. Как её удалить?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'undone'),
              child: const Text('Удалить как невыполненную'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'done'),
              child: const Text('Выполнена → удалить'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      wasDone = choice == 'done';
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Удалить выполненную задачу?'),
          content: Text(note.title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await FamilyService.instance.deleteNote(
      widget.space.id,
      note,
      wasDone: wasDone,
    );
    await _reload();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    await FamilyService.instance.sendMessage(widget.space.id, text);
    final msgs = await FamilyService.instance.messages(widget.space.id);
    if (mounted) setState(() => _messages = msgs);
  }

  /// Копирует ссылку-приглашение в буфер обмена.
  /// Пользователь сам вставляет её в удобный мессенджер.
  Future<void> _inviteByLink() async {
    try {
      final token =
          await FamilyService.instance.generateJoinCode(widget.space.id);
      final link = 'planer://join/$token';
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        showSnack(context, 'Ссылка скопирована');
      }
    } catch (e) {
      debugPrint('inviteByLink: $e');
      if (mounted) {
        showSnack(
          context,
          'Не удалось создать ссылку. Обновите пространство (кнопка «Обновить») и попробуйте снова.',
        );
      }
    }
  }

  Future<void> _invite() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        final emailCtrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Пригласить участника'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Имя (например: Мама, Алексей)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                [nameCtrl.text.trim(), emailCtrl.text.trim()],
              ),
              child: const Text('Отправить'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final name = result[0];
    final email = result[1];
    if (!email.contains('@')) {
      if (mounted) showSnack(context, 'Введите корректный email');
      return;
    }
    try {
      await FamilyService.instance.invite(
        spaceId: widget.space.id,
        email: email,
        displayName: name,
      );
      if (mounted) {
        showSnack(context, 'Приглашение отправлено на $email');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  String _memberName(String? uid) {
    if (uid == null) return '';
    for (final m in _members) {
      if (m.uid == uid) return m.displayName;
    }
    return uid.split('@').first;
  }

  bool get _isOwner {
    final uid = AuthService.instance.userKey.value;
    return _members.any((m) => m.uid == uid && m.role == 'owner');
  }

  void _showMembers() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Text(
                'Участники',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final m in _members)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppPalette.accent.withOpacity(0.2),
                    child: Text(
                      m.displayName.isNotEmpty
                          ? m.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(color: AppPalette.accent),
                    ),
                  ),
                  title: Text(m.displayName),
                  subtitle: Text(
                      m.role == 'owner' ? 'Владелец · ${m.email}' : m.email),
                  onTap: () => _editMemberName(ctx, m),
                  trailing: (_isOwner &&
                          m.role != 'owner' &&
                          m.uid != AuthService.instance.userKey.value)
                      ? IconButton(
                          tooltip: 'Удалить из группы',
                          icon: const Icon(Icons.person_remove_rounded,
                              color: AppPalette.rose),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: ctx,
                              builder: (d) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                title: Text('Удалить ${m.displayName}?'),
                                content: const Text(
                                  'Участник потеряет доступ к задачам и чату.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(d, false),
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(d, true),
                                    child: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await FamilyService.instance
                                  .removeMember(widget.space.id, m);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _reload();
                            }
                          },
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Действия меню пространства: выход участника / удаление создателем.
  Future<void> _handleSpaceMenu(String action) async {
    if (action == 'leave') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Выйти из пространства?'),
          content: Text(
            'Вы перестанете видеть задачи и чат «${widget.space.name}». '
            'Ваши сообщения и задачи останутся у других участников.',
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
      if (ok != true) return;
      try {
        await FamilyService.instance.leaveSpace(widget.space.id);
        if (!mounted) return;
        showSnack(context, 'Вы вышли из пространства');
        Navigator.pop(context);
      } catch (e) {
        if (mounted) showSnack(context, '$e');
      }
      return;
    }

    if (action == 'delete') {
      final count = _notes.length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text('Удалить «${widget.space.name}»?'),
          content: Text(
            'Пространство будет удалено вместе со всеми задачами '
            '($count шт.), перепиской и списком участников. '
            'Действие нельзя отменить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить навсегда'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await FamilyService.instance.deleteSpace(widget.space.id);
        if (!mounted) return;
        showSnack(context, 'Пространство удалено');
        Navigator.pop(context);
      } catch (e) {
        if (mounted) showSnack(context, '$e');
      }
    }
  }

  /// Редактирование имени и фамилии участника.
  /// Участник правит себя; владелец — любого.
  Future<void> _editMemberName(BuildContext ctx, FamilyMember m) async {
    final isSelf = m.uid == AuthService.instance.userKey.value;
    if (!_isOwner && !isSelf) return;
    final firstCtrl = TextEditingController(text: m.firstName);
    final lastCtrl = TextEditingController(text: m.lastName);
    final saved = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Имя участника'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Фамилия'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final first = firstCtrl.text.trim();
    final last = lastCtrl.text.trim();
    final full = [first, last].where((s) => s.isNotEmpty).join(' ');
    m.firstName = first;
    m.lastName = last;
    m.displayName = full.isNotEmpty ? full : m.email.split('@').first;
    await FamilyService.instance.saveMember(widget.space.id, m);
    if (ctx.mounted) Navigator.pop(ctx);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: ThemedBackground(
        assetPath: ThemeOption.night.backgroundAsset,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.space.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          GestureDetector(
                            onTap: _showMembers,
                            child: Row(
                              children: [
                                Text(
                                  'Участников: ${_members.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.accentSoft,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(Icons.people_rounded,
                                    size: 14, color: AppPalette.accentSoft),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Скопировать ссылку-приглашение',
                      onPressed: _inviteByLink,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Пригласить по email',
                      onPressed: _invite,
                      icon: const Icon(Icons.person_add_rounded),
                    ),
                    IconButton(
                      tooltip: 'Обновить',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Ещё',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: _handleSpaceMenu,
                      itemBuilder: (ctx) {
                        final isCreator =
                            widget.space.createdBy ==
                                AuthService.instance.userKey.value;
                        return [
                          if (!isCreator && !_isOwner)
                            const PopupMenuItem(
                              value: 'leave',
                              child: ListTile(
                                leading: Icon(Icons.logout_rounded),
                                title: Text('Выйти из пространства'),
                              ),
                            ),
                          if (isCreator)
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_forever_rounded,
                                    color: AppPalette.rose),
                                title: Text(
                                  'Удалить пространство',
                                  style: TextStyle(color: AppPalette.rose),
                                ),
                              ),
                            ),
                        ];
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegBtn(
                          label: 'Задачи',
                          icon: Icons.checklist_rounded,
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                      ),
                      Expanded(
                        child: _SegBtn(
                          label: 'Чат',
                          icon: Icons.chat_bubble_rounded,
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _tab == 0 ? _buildNotes() : _buildChat(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              heroTag: 'fab_family_note',
              onPressed: _addNote,
              backgroundColor: AppPalette.accent,
              foregroundColor: AppPalette.inkDeep,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Новая задача'),
            )
          : null,
    );
  }

  Widget _buildNotes() {
    final active = _notes.where((n) => !n.done).toList();
    final done = _notes.where((n) => n.done).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      children: [
        if (active.isEmpty && done.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Icon(Icons.checklist_rounded,
                      size: 48, color: AppPalette.accent),
                  const SizedBox(height: 12),
                  const Text(
                    'Пока нет задач',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Добавьте первую — её увидят все участники',
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ),
        ...active.map(_noteTile),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionTitle('ВЫПОЛНЕНО'),
          ...done.map(_noteTile),
        ],
      ],
    );
  }

  Widget _noteTile(FamilyNote note) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: note.done,
              onChanged: (_) => _toggle(note),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _showNoteDetail(note),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        decoration:
                            note.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (note.content.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (note.reminderDate != null)
                          _Badge(
                            icon: Icons.alarm_rounded,
                            text: DateFormat('d MMM HH:mm')
                                .format(note.reminderDate!),
                            color: AppPalette.rose,
                          ),
                        if (note.done && note.doneBy != null)
                          _Badge(
                            icon: Icons.check_rounded,
                            text: 'выполнил(а) ${_memberName(note.doneBy)}',
                            color: AppPalette.mint,
                          ),
                        _Badge(
                          icon: Icons.person_rounded,
                          text:
                              'создал(а) ${_memberName(note.createdBy)}',
                          color: AppPalette.sky,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Удалить может только создатель задачи.
            if (note.createdBy == AuthService.instance.userKey.value)
              IconButton(
                tooltip: 'Удалить',
                onPressed: () => _deleteNote(note),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  void _showNoteDetail(FamilyNote note) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (note.content.isNotEmpty) ...[
                Text(note.content),
                const SizedBox(height: 12),
              ],
              if (note.reminderDate != null)
                Text(
                  'Напоминание: ${DateFormat('d MMMM yyyy, HH:mm').format(note.reminderDate!)}',
                  style: const TextStyle(color: AppPalette.rose),
                ),
              const SizedBox(height: 8),
              Text(
                'Создал(а): ${_memberName(note.createdBy)}',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              if (note.done && note.doneBy != null)
                Text(
                  'Выполнил(а): ${_memberName(note.doneBy)}'
                  '${note.doneAt != null ? ' · ${DateFormat('d MMM yyyy, HH:mm').format(note.doneAt!)}' : ''}',
                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                ),
              if (note.createdBy == AuthService.instance.userKey.value) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _addNote(note);
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Изменить'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChat() {
    final myUid = AuthService.instance.userKey.value;
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'Напишите первое сообщение',
                    style: TextStyle(color: Colors.white.withOpacity(0.6)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  reverse: true,
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[_messages.length - 1 - i];
                    final mine = m.senderUid == myUid;
                    return _MsgBubble(msg: m, mine: mine);
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Эмодзи',
                onPressed: () {
                  showEmojiPicker(context, (e) {
                    _msgCtrl.text = _msgCtrl.text + e;
                    _msgCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: _msgCtrl.text.length),
                    );
                  });
                },
                icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    suffixIcon: DictationSuffix(controller: _msgCtrl),
                    hintText: 'Сообщение…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WhenButton extends StatelessWidget {
  const _WhenButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppPalette.accent.withOpacity(0.14)
          : Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? AppPalette.accent : Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppPalette.accent : Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
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

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppPalette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppPalette.inkDeep : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? AppPalette.inkDeep : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _MsgBubble extends StatelessWidget {
  const _MsgBubble({required this.msg, required this.mine});

  final FamilyMessage msg;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(msg.createdAt);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine
              ? AppPalette.accent.withOpacity(0.85)
              : Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              SelectableText(
                msg.senderName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.accentSoft,
                ),
              ),
            // SelectableText — чтобы можно было выделить и скопировать
            // текст сообщения (адрес, телефон, ссылку и т.п.).
            SelectableText(
              msg.text,
              style: TextStyle(
                color: mine ? AppPalette.inkDeep : Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: (mine ? AppPalette.inkDeep : Colors.white)
                    .withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

