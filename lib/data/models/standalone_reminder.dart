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
  final String id;
  String title;
  String? body;
  DateTime fireAt;
  bool done;

  /// id раздела; null — «Без раздела».
  String? sectionId;

  /// Повторять ежегодно (дни рождения, годовщины).
  bool yearly;

  String ownerKey;

  StandaloneReminder({
    required this.id,
    required this.title,
    this.body,
    required this.fireAt,
    this.done = false,
    this.sectionId,
    this.yearly = false,
    this.ownerKey = 'guest',
  });

  factory StandaloneReminder.create({
    required String title,
    String? body,
    required DateTime fireAt,
    String? sectionId,
    bool yearly = false,
    String ownerKey = 'guest',
  }) {
    final ms = DateTime.now().microsecondsSinceEpoch;
    return StandaloneReminder(
      id: 'r_${ms.toRadixString(16)}',
      title: title,
      body: body,
      fireAt: fireAt,
      sectionId: sectionId,
      yearly: yearly,
      ownerKey: ownerKey,
    );
  }

  /// Дата следующего ежегодного срабатывания (та же дата/время через год).
  DateTime nextYear() => DateTime(
        fireAt.year + 1,
        fireAt.month,
        fireAt.day,
        fireAt.hour,
        fireAt.minute,
      );

  bool get hasSection => sectionId != null;

  StandaloneReminder copyWith({
    String? title,
    String? body,
    bool clearBody = false,
    DateTime? fireAt,
    bool? done,
    String? sectionId,
    bool clearSection = false,
    bool? yearly,
    String? ownerKey,
  }) {
    return StandaloneReminder(
      id: id,
      title: title ?? this.title,
      body: clearBody ? null : (body ?? this.body),
      fireAt: fireAt ?? this.fireAt,
      done: done ?? this.done,
      sectionId: clearSection ? null : (sectionId ?? this.sectionId),
      yearly: yearly ?? this.yearly,
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
        yearly: json['yearly'] == true,
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      );

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'title': title,
        'body': body,
        'fireAt': fireAt.millisecondsSinceEpoch,
        'done': done,
        'sectionId': sectionId,
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
        yearly: json['yearly'] == true,
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      );
}

int _uuidSeq = 0;

String _uuid(String prefix) {
  _uuidSeq = (_uuidSeq + 1) & 0xffffff;
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = (_uuidSeq * 2654435761 & 0xffffff).toRadixString(36);
  return '${prefix}_${t}_${_uuidSeq.toRadixString(36)}$r';
}
