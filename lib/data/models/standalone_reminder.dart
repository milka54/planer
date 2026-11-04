/// Раздел напоминаний («Дни рождения», «Врачи»…).
class ReminderSection {
  final String id;
  String title;
  int colorIndex;
  final DateTime createdAt;
  DateTime updatedAt;
  String ownerKey;

  ReminderSection({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.colorIndex = 0,
    required this.ownerKey,
  });

  factory ReminderSection.create({
    required String title,
    required String ownerKey,
    int colorIndex = 0,
  }) {
    final now = DateTime.now();
    return ReminderSection(
      id: _uuid('rs'),
      title: title,
      createdAt: now,
      updatedAt: now,
      colorIndex: colorIndex,
      ownerKey: ownerKey,
    );
  }

  ReminderSection copyWith({String? title, int? colorIndex, String? ownerKey}) {
    return ReminderSection(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      colorIndex: colorIndex ?? this.colorIndex,
      ownerKey: ownerKey ?? this.ownerKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorIndex': colorIndex,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'ownerKey': ownerKey,
      };

  factory ReminderSection.fromJson(Map<String, dynamic> json) =>
      ReminderSection(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(
          (json['updatedAt'] as String?) ?? json['createdAt'] as String,
        ),
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      );

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'title': title,
        'colorIndex': colorIndex,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'ownerKey': ownerKey,
      };

  factory ReminderSection.fromFirestore(Map<String, dynamic> json) =>
      ReminderSection(
        id: json['id'] as String? ?? '',
        title: (json['title'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ??
              (json['createdAt'] as num?)?.toInt() ??
              0,
        ),
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      );
}

/// Напоминание: заголовок, описание, дата/время, раздел, повтор.
class StandaloneReminder {
  /// Типы повтора: без повтора, ежегодно, каждые N дней, по дням недели.
  static const repeatNone = 'none';
  static const repeatYearly = 'yearly';
  static const repeatEveryN = 'everyN';
  static const repeatWeekly = 'weekly';

  final String id;
  String title;
  String? body;
  DateTime fireAt;
  bool done;

  /// id раздела; null — «Без раздела».
  String? sectionId;

  /// Тип повтора (см. repeatNone/repeatYearly/repeatEveryN/repeatWeekly).
  String repeatType;

  /// Интервал в днях для repeatEveryN.
  int repeatEvery;

  /// Дни недели для repeatWeekly: 1=Пн … 7=Вс.
  List<int> weekdays;

  String ownerKey;

  StandaloneReminder({
    required this.id,
    required this.title,
    this.body,
    required this.fireAt,
    this.done = false,
    this.sectionId,
    this.repeatType = repeatNone,
    this.repeatEvery = 1,
    List<int>? weekdays,
    this.ownerKey = 'guest',
  }) : weekdays = weekdays ?? [];

  factory StandaloneReminder.create({
    required String title,
    String? body,
    required DateTime fireAt,
    String? sectionId,
    String repeatType = repeatNone,
    int repeatEvery = 1,
    List<int>? weekdays,
    String ownerKey = 'guest',
  }) {
    final ms = DateTime.now().microsecondsSinceEpoch;
    return StandaloneReminder(
      id: 'r_${ms.toRadixString(16)}',
      title: title,
      body: body,
      fireAt: fireAt,
      sectionId: sectionId,
      repeatType: repeatType,
      repeatEvery: repeatEvery,
      weekdays: weekdays,
      ownerKey: ownerKey,
    );
  }

  bool get yearly => repeatType == repeatYearly;
  bool get hasRepeat => repeatType != repeatNone;

  /// Дата следующего ежегодного срабатывания (та же дата/время через год).
  DateTime nextYear() => DateTime(
        fireAt.year + 1,
        fireAt.month,
        fireAt.day,
        fireAt.hour,
        fireAt.minute,
      );

  /// Следующее срабатывание строго после [after] (по умолчанию — сейчас).
  /// null — если повтора нет.
  DateTime? nextOccurrence([DateTime? after]) {
    final from = after ?? DateTime.now();
    switch (repeatType) {
      case repeatYearly:
        var next = nextYear();
        while (!next.isAfter(from)) {
          next = DateTime(
            next.year + 1,
            fireAt.month,
            fireAt.day,
            fireAt.hour,
            fireAt.minute,
          );
        }
        return next;
      case repeatEveryN:
        final n = repeatEvery.clamp(1, 365);
        var next = fireAt;
        while (!next.isAfter(from)) {
          next = next.add(Duration(days: n));
        }
        return next;
      case repeatWeekly:
        if (weekdays.isEmpty) return null;
        var candidate = DateTime(
          from.year,
          from.month,
          from.day,
          fireAt.hour,
          fireAt.minute,
        );
        for (var i = 0; i < 8; i++) {
          if (candidate.isAfter(from) && weekdays.contains(candidate.weekday)) {
            return candidate;
          }
          candidate = candidate.add(const Duration(days: 1));
        }
        return null;
      default:
        return null;
    }
  }

  /// Человекочитаемое описание повтора (для списков и формы).
  String repeatLabel({bool short = false}) {
    switch (repeatType) {
      case repeatYearly:
        return 'Каждый год';
      case repeatEveryN:
        return repeatEvery == 1
            ? 'Каждый день'
            : 'Каждые $repeatEvery дн.';
      case repeatWeekly:
        if (weekdays.isEmpty) return 'По дням недели';
        const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
        final sorted = [...weekdays]..sort();
        return 'По ${sorted.map((d) => names[d - 1]).join(', ')}';
      default:
        return short ? '' : 'Без повтора';
    }
  }

  bool get hasSection => sectionId != null;

  StandaloneReminder copyWith({
    String? title,
    String? body,
    bool clearBody = false,
    DateTime? fireAt,
    bool? done,
    String? sectionId,
    bool clearSection = false,
    String? repeatType,
    int? repeatEvery,
    List<int>? weekdays,
    bool clearWeekdays = false,
    String? ownerKey,
  }) {
    return StandaloneReminder(
      id: id,
      title: title ?? this.title,
      body: clearBody ? null : (body ?? this.body),
      fireAt: fireAt ?? this.fireAt,
      done: done ?? this.done,
      sectionId: clearSection ? null : (sectionId ?? this.sectionId),
      repeatType: repeatType ?? this.repeatType,
      repeatEvery: repeatEvery ?? this.repeatEvery,
      weekdays: clearWeekdays ? [] : (weekdays ?? this.weekdays),
      ownerKey: ownerKey ?? this.ownerKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'fireAt': fireAt.toIso8601String(),
        'done': done,
        'sectionId': sectionId,
        'repeatType': repeatType,
        'repeatEvery': repeatEvery,
        'weekdays': weekdays,
        'yearly': yearly,
        'ownerKey': ownerKey,
      };

  factory StandaloneReminder.fromJson(Map<String, dynamic> json) =>
      StandaloneReminder(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        body: json['body'] as String?,
        fireAt: DateTime.parse(json['fireAt'] as String),
        done: json['done'] == true,
        sectionId: json['sectionId'] as String?,
        repeatType: _readRepeatType(json),
        repeatEvery: (json['repeatEvery'] as num?)?.toInt() ?? 1,
        weekdays: (json['weekdays'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      );

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'title': title,
        'body': body,
        'fireAt': fireAt.millisecondsSinceEpoch,
        'done': done,
        'sectionId': sectionId,
        'repeatType': repeatType,
        'repeatEvery': repeatEvery,
        'weekdays': weekdays,
        'yearly': yearly,
        'ownerKey': ownerKey,
      };

  factory StandaloneReminder.fromFirestore(Map<String, dynamic> json) =>
      StandaloneReminder(
        id: json['id'] as String? ?? '',
        title: (json['title'] as String?) ?? '',
        body: json['body'] as String?,
        fireAt: DateTime.fromMillisecondsSinceEpoch(
          (json['fireAt'] as num?)?.toInt() ?? 0,
        ),
        done: json['done'] == true,
        sectionId: json['sectionId'] as String?,
        repeatType: _readRepeatType(json),
        repeatEvery: (json['repeatEvery'] as num?)?.toInt() ?? 1,
        weekdays: (json['weekdays'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      );
}

/// Старые записи имели только флаг yearly — мигрируем на repeatType.
String _readRepeatType(Map<String, dynamic> json) {
  final raw = json['repeatType'] as String?;
  if (raw != null) return raw;
  return json['yearly'] == true
      ? StandaloneReminder.repeatYearly
      : StandaloneReminder.repeatNone;
}

int _uuidSeq = 0;

String _uuid(String prefix) {
  _uuidSeq = (_uuidSeq + 1) & 0xffffff;
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = (_uuidSeq * 2654435761 & 0xffffff).toRadixString(36);
  return '${prefix}_${t}_${_uuidSeq.toRadixString(36)}$r';
}
