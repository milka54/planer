import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/models/standalone_reminder.dart';

/// Правило повтора для формы напоминания.
typedef RepeatRule = ({
  String type,
  int every,
  List<int> weekdays,
});

/// Диалог выбора повтора: без повтора / каждый год / каждые N дней / дни недели.
/// Возвращает правило или null (отмена).
Future<RepeatRule?> showRepeatRulePicker(
  BuildContext context, {
  required RepeatRule initial,
}) {
  var type = initial.type;
  var every = initial.every;
  var days = {...initial.weekdays};
  final everyCtrl = TextEditingController(text: '${initial.every}');

  return showDialog<RepeatRule>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Повтор'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: StandaloneReminder.repeatNone,
                  groupValue: type,
                  dense: true,
                  title: const Text('Без повтора'),
                  onChanged: (v) => setDialog(() => type = v!),
                ),
                RadioListTile<String>(
                  value: StandaloneReminder.repeatYearly,
                  groupValue: type,
                  dense: true,
                  title: const Text('Каждый год'),
                  subtitle: const Text('Дни рождения, годовщины'),
                  onChanged: (v) => setDialog(() => type = v!),
                ),
                RadioListTile<String>(
                  value: StandaloneReminder.repeatEveryN,
                  groupValue: type,
                  dense: true,
                  title: const Text('Каждые N дней'),
                  onChanged: (v) => setDialog(() => type = v!),
                ),
                if (type == StandaloneReminder.repeatEveryN)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: TextField(
                            controller: everyCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n > 0) every = n;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('дней'),
                      ],
                    ),
                  ),
                RadioListTile<String>(
                  value: StandaloneReminder.repeatWeekly,
                  groupValue: type,
                  dense: true,
                  title: const Text('По дням недели'),
                  onChanged: (v) => setDialog(() => type = v!),
                ),
                if (type == StandaloneReminder.repeatWeekly)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(7, (i) {
                        final day = i + 1;
                        final selected = days.contains(day);
                        return FilterChip(
                          label: Text(names[i]),
                          selected: selected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (v) => setDialog(() {
                            if (v) {
                              days.add(day);
                            } else {
                              days.remove(day);
                            }
                          }),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (type == StandaloneReminder.repeatEveryN &&
                    (every < 1 || every > 365)) {
                  return;
                }
                if (type == StandaloneReminder.repeatWeekly && days.isEmpty) {
                  return;
                }
                Navigator.pop(
                  ctx,
                  (type: type, every: every, weekdays: days.toList()..sort()),
                );
              },
              child: const Text('Готово'),
            ),
          ],
        );
      },
    ),
  );
}

/// Диалог установки напоминания с ОТДЕЛЬНЫМИ полями «Дата» и «Время».
///
/// Пользователь сразу видит оба поля — не нужно «пройти дальше»,
/// чтобы понять, что время тоже можно выбрать.
/// Возвращает выбранное время или null (отмена / не задано).
Future<DateTime?> showReminderDateTimePicker(
  BuildContext context, {
  DateTime? initial,
  bool allowClear = false,
}) {
  DateTime date = initial ?? DateTime.now();
  TimeOfDay time = TimeOfDay.fromDateTime(initial ?? DateTime.now());
  bool hasDate = initial != null;
  bool hasTime = initial != null;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        final dateLabel = hasDate
            ? DateFormat('d MMMM yyyy', 'ru').format(date)
            : 'Не выбрана';
        final timeLabel = hasTime
            ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
            : 'Не выбрано';
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Icon(Icons.alarm_add_rounded,
                  color: AppPalette.accent, size: 22),
              const SizedBox(width: 8),
              const Text('Напоминание'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PickerRow(
                icon: Icons.calendar_month_rounded,
                label: 'Дата',
                value: dateLabel,
                selected: hasDate,
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: hasDate ? date : DateTime.now(),
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  );
                  if (d != null) {
                    setDialog(() {
                      date = d;
                      hasDate = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              _PickerRow(
                icon: Icons.schedule_rounded,
                label: 'Время',
                value: timeLabel,
                selected: hasTime,
                onTap: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: hasTime ? time : TimeOfDay.now(),
                  );
                  if (t != null) {
                    setDialog(() {
                      time = t;
                      hasTime = true;
                    });
                  }
                },
              ),
              if (allowClear) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Убрать напоминание'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (!hasDate && !hasTime) {
                  Navigator.pop(ctx, null);
                  return;
                }
                final d = hasDate ? date : DateTime.now();
                final t = hasTime ? time : TimeOfDay.now();
                Navigator.pop(
                  ctx,
                  DateTime(d.year, d.month, d.day, t.hour, t.minute),
                );
              },
              child: const Text('Готово'),
            ),
          ],
        );
      },
    ),
  );
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
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
          ? AppPalette.accent.withOpacity(0.12)
          : Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppPalette.accent : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppPalette.accent : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
