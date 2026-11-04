import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/models/standalone_reminder.dart';

void main() {
  StandaloneReminder rem({
    DateTime? fireAt,
    String repeatType = StandaloneReminder.repeatNone,
    int repeatEvery = 1,
    List<int>? weekdays,
  }) {
    return StandaloneReminder.create(
      title: 't',
      fireAt: fireAt ?? DateTime(2026, 6, 10, 9, 0),
      repeatType: repeatType,
      repeatEvery: repeatEvery,
      weekdays: weekdays,
    );
  }

  group('nextOccurrence', () {
    test('без повтора — null', () {
      expect(rem().nextOccurrence(), isNull);
    });

    test('каждый год — та же дата через год', () {
      final r = rem(repeatType: StandaloneReminder.repeatYearly);
      final next = r.nextOccurrence(DateTime(2026, 7, 1));
      expect(next, DateTime(2027, 6, 10, 9, 0));
    });

    test('каждый год — перенос через несколько лет', () {
      final r = rem(repeatType: StandaloneReminder.repeatYearly);
      final next = r.nextOccurrence(DateTime(2030, 1, 1));
      expect(next, DateTime(2030, 6, 10, 9, 0));
    });

    test('каждые N дней', () {
      final r = rem(
        repeatType: StandaloneReminder.repeatEveryN,
        repeatEvery: 3,
      );
      // 10 июня + 3 дня, если "сейчас" 11 июня
      final next = r.nextOccurrence(DateTime(2026, 6, 11));
      expect(next, DateTime(2026, 6, 13, 9, 0));
    });

    test('каждые N дней — далеко в прошлом докатывается вперёд', () {
      final r = rem(
        fireAt: DateTime(2026, 1, 1, 8, 0),
        repeatType: StandaloneReminder.repeatEveryN,
        repeatEvery: 2,
      );
      final next = r.nextOccurrence(DateTime(2026, 6, 10, 0, 0));
      expect(next!.isAfter(DateTime(2026, 6, 10)), isTrue);
      // шаг 2 дня сохраняется
      final days = next!.difference(DateTime(2026, 1, 1, 8, 0)).inDays;
      expect(days % 2, 0);
    });

    test('по дням недели — ближайший выбранный день', () {
      // 10.06.2026 — среда (weekday=3). Повтор по Пн(1) и Сб(6).
      final r = rem(
        fireAt: DateTime(2026, 6, 10, 9, 0),
        repeatType: StandaloneReminder.repeatWeekly,
        weekdays: [1, 6],
      );
      final next = r.nextOccurrence(DateTime(2026, 6, 10, 10, 0));
      expect(next, DateTime(2026, 6, 13, 9, 0)); // суббота
      final after = r.nextOccurrence(DateTime(2026, 6, 13, 10, 0));
      expect(after, DateTime(2026, 6, 15, 9, 0)); // понедельник
    });

    test('по дням недели — пустой список → null', () {
      final r = rem(repeatType: StandaloneReminder.repeatWeekly);
      expect(r.nextOccurrence(), isNull);
    });
  });

  group('миграция и сериализация', () {
    test('старый yearly=true мигрирует в repeatYearly', () {
      final r = StandaloneReminder.fromJson({
        'id': 'x',
        'title': 'день рождения',
        'fireAt': DateTime(2026, 6, 10).toIso8601String(),
        'yearly': true,
      });
      expect(r.repeatType, StandaloneReminder.repeatYearly);
      expect(r.yearly, isTrue);
    });

    test('roundtrip json с repeat-полями', () {
      final r = rem(
        repeatType: StandaloneReminder.repeatWeekly,
        weekdays: [1, 3, 5],
      );
      final back = StandaloneReminder.fromJson(r.toJson());
      expect(back.repeatType, StandaloneReminder.repeatWeekly);
      expect(back.weekdays, [1, 3, 5]);
      expect(back.repeatEvery, 1);
    });

    test('repeatLabel для типов', () {
      expect(
        rem(repeatType: StandaloneReminder.repeatYearly).repeatLabel(),
        'Каждый год',
      );
      expect(
        rem(repeatType: StandaloneReminder.repeatEveryN, repeatEvery: 5)
            .repeatLabel(),
        'Каждые 5 дн.',
      );
      expect(
        rem(repeatType: StandaloneReminder.repeatWeekly, weekdays: [2, 4])
            .repeatLabel(),
        'По Вт, Чт',
      );
    });
  });
}
