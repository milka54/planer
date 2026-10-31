import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/models/standalone_reminder.dart';
import '../data/reminder_service.dart';
import 'reminder_time_picker.dart';
import 'widgets.dart';

/// Полноэкранный календарь: смотреть день и добавлять напоминания.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();

  List<DateTime> _daysGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final startOffset = first.weekday - 1; // Пн=0
    final start = first.subtract(Duration(days: startOffset));
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }

  Future<void> _addReminder({StandaloneReminder? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    DateTime fireAt = existing?.fireAt ??
        DateTime(
          _selected.year,
          _selected.month,
          _selected.day,
          DateTime.now().hour + 1,
          0,
        );
    String? sectionId = existing?.sectionId;
    bool yearly = existing?.yearly ?? false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null
                        ? 'Новое напоминание'
                        : 'Изменить напоминание',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Без заметки — просто уведомление',
                    style: TextStyle(
                      color: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withOpacity(0.55),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    autofocus: existing == null,
                    decoration: const InputDecoration(
                      hintText: 'Что напомнить?',
                      prefixIcon: Icon(Icons.notification_add_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bodyCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Комментарий (необязательно)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassPanel(
                    glow: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.event_rounded),
                      title: const Text('Дата и время'),
                      subtitle: Text(formatDateTimeRu(fireAt)),
                      trailing: const Icon(Icons.edit_calendar_rounded),
                      onTap: () async {
                        final picked = await showReminderDateTimePicker(
                          context,
                          initial: fireAt,
                        );
                        if (picked == null) return;
                        setModal(() => fireAt = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  GlassPanel(
                    glow: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.folder_open_rounded),
                      title: const Text('Раздел'),
                      subtitle: Text(
                        ReminderService.instance
                                .sectionById(sectionId)
                                ?.title ??
                            'Без раздела',
                      ),
                      trailing: const Icon(Icons.expand_more_rounded),
                      onTap: () async {
                        final picked =
                            await _pickSection(ctx, sectionId: sectionId);
                        if (picked != null) {
                          setModal(() => sectionId = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  GlassPanel(
                    glow: false,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SwitchListTile(
                      secondary: const Icon(Icons.repeat_rounded),
                      title: const Text('Повторять ежегодно'),
                      subtitle: const Text('Дни рождения, годовщины'),
                      value: yearly,
                      onChanged: (v) => setModal(() => yearly = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: existing == null
                        ? 'Добавить напоминание'
                        : 'Сохранить',
                    icon: Icons.check_rounded,
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) {
                        showSnack(ctx, 'Введите текст напоминания');
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                  ),
                  if (existing != null)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Удалить',
                        style: TextStyle(color: AppPalette.rose),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      final title = titleCtrl.text.trim();
      final body = bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim();
      if (existing == null) {
        await ReminderService.instance.add(
          StandaloneReminder.create(
            title: title,
            body: body,
            fireAt: fireAt,
            sectionId: sectionId,
            yearly: yearly,
          ),
        );
      } else {
        await ReminderService.instance.update(
          existing.copyWith(
            title: title,
            body: body,
            clearBody: body == null,
            fireAt: fireAt,
            sectionId: sectionId,
            clearSection: sectionId == null,
            yearly: yearly,
          ),
        );
      }
    } else if (saved == false && existing != null) {
      await ReminderService.instance.remove(existing);
    }

    titleCtrl.dispose();
    bodyCtrl.dispose();
    if (mounted) setState(() {});
  }

  /// Возвращает id выбранного раздела или null («Без раздела»).
  /// Если пользователь создал новый раздел — возвращает его id.
  Future<String?> _pickSection(BuildContext ctx,
      {String? sectionId}) async {
    final result = await showModalBottomSheet<String?>(
      context: ctx,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: ValueListenableBuilder<List<ReminderSection>>(
          valueListenable: ReminderService.instance.sections,
          builder: (context, sections, _) {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Раздел напоминания',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_off_rounded),
                  title: const Text('Без раздела'),
                  trailing: sectionId == null
                      ? const Icon(Icons.check_rounded,
                          color: AppPalette.accent)
                      : null,
                  onTap: () => Navigator.pop(sheetCtx, ''),
                ),
                for (final s in sections)
                  ListTile(
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppPalette
                            .noteColors[s.colorIndex % AppPalette.noteColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(s.title),
                    trailing: sectionId == s.id
                        ? const Icon(Icons.check_rounded,
                            color: AppPalette.accent)
                        : null,
                    onTap: () => Navigator.pop(sheetCtx, s.id),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined,
                      color: AppPalette.accent),
                  title: const Text(
                    'Создать раздел',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    final created =
                        await showCreateReminderSectionDialog(sheetCtx);
                    if (created != null && sheetCtx.mounted) {
                      Navigator.pop(sheetCtx, created.id);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
    if (result == null) return sectionId;
    return result.isEmpty ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final days = _daysGrid();
    final dayNotes = ReminderService.instance.onDay(_selected);

    return Scaffold(
      backgroundColor: dark ? AppPalette.inkDeep : AppPalette.paper,
      appBar: AppBar(
        title: const Text('Календарь'),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Добавить',
            onPressed: () => _addReminder(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month - 1);
                  }),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    DateFormat('LLLL yyyy', 'ru_RU').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month + 1);
                  }),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, i) {
                final day = days[i];
                final inMonth = day.month == _month.month;
                final isToday = _sameDay(day, DateTime.now());
                final isSelected = _sameDay(day, _selected);
                final marks = ReminderService.instance.onDay(day).length;

                return GestureDetector(
                  onTap: () => setState(() => _selected = day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppPalette.accent.withOpacity(0.85)
                          : isToday
                              ? AppPalette.accent.withOpacity(0.18)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: isToday && !isSelected
                          ? Border.all(
                              color: AppPalette.accent.withOpacity(0.55),
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontWeight:
                                isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : inMonth
                                    ? null
                                    : Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withOpacity(0.35),
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (marks > 0)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : AppPalette.accent,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(height: 6),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('d MMMM yyyy', 'ru_RU').format(_selected),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _addReminder(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (dayNotes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'В этот день напоминаний нет',
                        style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.5),
                        ),
                      ),
                    ),
                  )
                else
                  ...dayNotes.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Dismissible(
                        key: ValueKey(r.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppPalette.rose.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) {
                          ReminderService.instance.remove(r);
                          setState(() {});
                        },
                        child: GlassPanel(
                          glow: false,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Checkbox(
                              value: r.done,
                              onChanged: (_) async {
                                await ReminderService.instance.toggleDone(r);
                                setState(() {});
                              },
                            ),
                            title: Text(
                              r.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: r.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              [
                                formatDateTimeRu(r.fireAt),
                                if (r.body != null && r.body!.isNotEmpty)
                                  r.body!,
                              ].join(' · '),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 20),
                              onPressed: () => _addReminder(existing: r),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addReminder(),
        backgroundColor: AppPalette.accent,
        foregroundColor: AppPalette.inkDeep,
        icon: const Icon(Icons.notification_add_rounded),
        label: const Text('Напоминание'),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Диалог создания раздела напоминаний («Дни рождения», «Врачи»…).
Future<ReminderSection?> showCreateReminderSectionDialog(
  BuildContext context,
) async {
  final ctrl = TextEditingController();
  int colorIndex = 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Новый раздел'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Например: Дни рождения',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Цвет',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AppPalette.noteColors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == colorIndex;
                  return GestureDetector(
                    onTap: () => setDialog(() => colorIndex = i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppPalette.noteColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) {
                showSnack(ctx, 'Введите название раздела');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) {
    ctrl.dispose();
    return null;
  }
  final section = await ReminderService.instance.createSection(
    title: ctrl.text.trim(),
    colorIndex: colorIndex,
  );
  ctrl.dispose();
  return section;
}
