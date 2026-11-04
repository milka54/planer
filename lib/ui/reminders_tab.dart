import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/models/standalone_reminder.dart';
import '../data/notes_repository.dart';
import '../data/reminder_service.dart';
import 'calendar_screen.dart';
import 'note_detail.dart';
import 'widgets.dart';

class RemindersTab extends StatefulWidget {
  const RemindersTab({super.key});

  @override
  State<RemindersTab> createState() => _RemindersTabState();
}

class _RemindersTabState extends State<RemindersTab> {
  @override
  void initState() {
    super.initState();
    ReminderService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        NotesRepository.instance.notes,
        ReminderService.instance.reminders,
      ]),
      builder: (context, _) {
        final noteReminders = NotesRepository.instance.remindersSorted;
        final now = DateTime.now();
        final noteUpcoming =
            noteReminders.where((n) => n.reminderDate!.isAfter(now)).toList();
        final notePast = noteReminders
            .where((n) => n.reminderDate!.isBefore(now))
            .toList()
            .reversed
            .toList();

        final customUpcoming = ReminderService.instance.upcoming();
        final customPast = ReminderService.instance.past();

        final empty = noteUpcoming.isEmpty &&
            notePast.isEmpty &&
            customUpcoming.isEmpty &&
            customPast.isEmpty;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            Row(
              children: [
                const Expanded(child: MagazineTitle('Напоминания')),
                IconButton.filledTonal(
                  tooltip: 'Календарь',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CalendarScreen()),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              empty
                  ? 'Планируйте время и дела'
                  : 'Всего событий: ${noteUpcoming.length + customUpcoming.length}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 12),
            GlassPanel(
              glow: true,
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppPalette.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: AppPalette.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Календарь напоминаний',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Добавить уведомление без заметки',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CalendarScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            if (noteUpcoming.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionTitle('ИЗ ЗАМЕТОК'),
              ...noteUpcoming.asMap().entries.map(
                    (e) => StaggeredFadeIn(
                      index: e.key,
                      child: _NoteReminderTile(
                        note: e.value,
                        past: false,
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: SectionTitle('НАПОМИНАНИЯ')),
                IconButton.filledTonal(
                  tooltip: 'Новый раздел',
                  onPressed: () async {
                    await showCreateReminderSectionDialog(context);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
                IconButton.filled(
                  tooltip: 'Новое напоминание',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CalendarScreen()),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            for (final s in ReminderService.instance.allSections)
              _ReminderSectionGroup(
                section: s,
                onChanged: () => setState(() {}),
              ),
            if (ReminderService.instance.remindersIn(null).isNotEmpty)
              _ReminderGroup(
                title: 'Без раздела',
                color: AppPalette.sky,
                reminders: ReminderService.instance.remindersIn(null),
                onChanged: () => setState(() {}),
              ),
            if (empty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 36),
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppPalette.accent.withOpacity(0.22),
                              AppPalette.rose.withOpacity(0.16),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Icon(
                          Icons.alarm_add_rounded,
                          size: 42,
                          color: AppPalette.accent,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Планируйте время',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Создайте раздел (например «Дни рождения»)\n'
                        'или добавьте напоминание',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () async {
                              await showCreateReminderSectionDialog(context);
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('Новый раздел'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CalendarScreen(),
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.add_alert_rounded),
                            label: const Text('Новое напоминание'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (customPast.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionTitle('ПРОШЕДШИЕ'),
              ...customPast.take(6).map(
                    (r) => _CustomReminderTile(
                      reminder: r,
                      past: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
            ],
            if (notePast.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...notePast.take(4).map(
                    (n) => _NoteReminderTile(note: n, past: true),
                  ),
            ],
          ],
        );
      },
    );
  }
}

class _NoteReminderTile extends StatelessWidget {
  final Note note;
  final bool past;
  const _NoteReminderTile({required this.note, required this.past});

  @override
  Widget build(BuildContext context) {
    final color = AppPalette
        .noteColors[note.colorIndex % AppPalette.noteColors.length];
    final when = note.reminderDate!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: past
            ? (Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.04))
            : (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E2F52)
                : AppPalette.paperCard),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: past ? Colors.black12 : color.withOpacity(0.45),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(past ? 0.12 : 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${when.day}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: past ? Colors.black45 : color,
                        ),
                      ),
                      Text(
                        _month(when.month),
                        style: TextStyle(
                          fontSize: 10,
                          color: past ? Colors.black38 : color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title.isEmpty ? 'Без названия' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatRelative(when)} · ${formatDateTimeRu(when)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const NoteChip(
                  icon: Icons.notes_rounded,
                  label: 'заметка',
                  color: AppPalette.sky,
                ),
                IconButton(
                  tooltip: 'Убрать напоминание',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22)),
                        title: const Text('Убрать напоминание?'),
                        content: Text(
                          '«${note.title.isEmpty ? 'Без названия' : note.title}»\n\n'
                          'Заметка останется — уберётся только напоминание.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Убрать'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await NotesRepository.instance.setReminder(note, null);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _month(int m) {
    const names = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return names[m - 1];
  }
}

/// Раздел напоминаний: заголовок + вложенные напоминания.
class _ReminderSectionGroup extends StatelessWidget {
  final ReminderSection section;
  final VoidCallback onChanged;

  const _ReminderSectionGroup({
    required this.section,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppPalette
        .noteColors[section.colorIndex % AppPalette.noteColors.length];
    final items = ReminderService.instance.remindersIn(section.id);
    return _ReminderGroup(
      title: section.title,
      color: color,
      reminders: items,
      onChanged: onChanged,
      onDelete: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text('Удалить раздел «${section.title}»?'),
            content: const Text(
              'Напоминания останутся и перейдут в «Без раздела».',
            ),
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
        if (ok == true) {
          await ReminderService.instance.deleteSection(section);
          onChanged();
        }
      },
    );
  }
}

class _ReminderGroup extends StatelessWidget {
  final String title;
  final Color color;
  final List<StandaloneReminder> reminders;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  const _ReminderGroup({
    required this.title,
    required this.color,
    required this.reminders,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final upcoming = reminders.where((r) => !r.done && r.fireAt.isAfter(DateTime.now())).toList();
    final doneOrPast = reminders.where((r) => !upcoming.contains(r)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        glow: false,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$title · ${reminders.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (onDelete != null)
                  SoftIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Удалить раздел',
                    onPressed: onDelete,
                  ),
              ],
            ),
            if (reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                child: Text(
                  'Пока пусто — добавьте напоминание в календаре',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.5),
                  ),
                ),
              ),
            ...upcoming.map(
              (r) => _CustomReminderTile(
                reminder: r,
                past: false,
                onChanged: onChanged,
              ),
            ),
            ...doneOrPast.map(
              (r) => _CustomReminderTile(
                reminder: r,
                past: true,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomReminderTile extends StatelessWidget {
  final StandaloneReminder reminder;
  final bool past;
  final VoidCallback onChanged;

  const _CustomReminderTile({
    required this.reminder,
    required this.past,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        glow: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          leading: Checkbox(
            value: reminder.done,
            onChanged: (_) async {
              await ReminderService.instance.toggleDone(reminder);
              onChanged();
            },
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  reminder.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration:
                        reminder.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (reminder.hasRepeat)
                Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.repeat_rounded,
                    size: 16,
                    color: AppPalette.accent,
                  ),
                ),
            ],
          ),
          subtitle: Text(
            reminder.body == null || reminder.body!.trim().isEmpty
                ? '${formatDateTimeRu(reminder.fireAt)}${reminder.hasRepeat ? ' · ${reminder.repeatLabel(short: true)}' : ''}'
                : '${reminder.body} · ${formatDateTimeRu(reminder.fireAt)}${reminder.hasRepeat ? ' · ${reminder.repeatLabel(short: true)}' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (past)
                const Icon(Icons.history_rounded, color: Colors.black26)
              else
                PulseIcon(
                  icon: Icons.notifications_active_rounded,
                  color: AppPalette.accent,
                  size: 20,
                ),
              IconButton(
                tooltip: 'Удалить напоминание',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                      title: const Text('Удалить напоминание?'),
                      content: Text('«${reminder.title}»'),
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
                  if (ok == true) {
                    await ReminderService.instance.remove(reminder);
                    onChanged();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
