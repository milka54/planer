/// Раздел заметок («Записи к врачам», «Работа»…).
class NoteSection {
  final String id;
  String title;
  int colorIndex;
  final DateTime createdAt;
  DateTime updatedAt;
  String ownerKey;

  NoteSection({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.colorIndex = 0,
    required this.ownerKey,
  });

  factory NoteSection.create({
    required String title,
    required String ownerKey,
    int colorIndex = 0,
  }) {
    final now = DateTime.now();
    return NoteSection(
      id: _uuid('s'),
      title: title,
      createdAt: now,
      updatedAt: now,
      colorIndex: colorIndex,
      ownerKey: ownerKey,
    );
  }

  NoteSection copyWith({String? title, int? colorIndex, String? ownerKey}) {
    return NoteSection(
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

  factory NoteSection.fromJson(Map<String, dynamic> json) => NoteSection(
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

  factory NoteSection.fromFirestore(Map<String, dynamic> json) => NoteSection(
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

/// Заметка: заголовок, текст, напоминание, вложения-голос.
class Note {
  final String id;
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? reminderDate;
  int colorIndex;
  bool pinned;
  bool archived;
  String ownerKey;

  /// id раздела; null — «Без раздела».
  String? sectionId;

  /// Локальные пути к голосовым вложениям.
  List<String> voicePaths;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.reminderDate,
    this.colorIndex = 0,
    this.pinned = false,
    this.archived = false,
    required this.ownerKey,
    this.sectionId,
    List<String>? voicePaths,
  }) : voicePaths = voicePaths ?? [];

  factory Note.create({
    required String title,
    required String content,
    required String ownerKey,
    String? sectionId,
    DateTime? reminderDate,
    int colorIndex = 0,
    List<String>? voicePaths,
  }) {
    final now = DateTime.now();
    return Note(
      id: _uuid('n'),
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      reminderDate: reminderDate,
      colorIndex: colorIndex,
      ownerKey: ownerKey,
      sectionId: sectionId,
      voicePaths: voicePaths ?? [],
    );
  }

  bool get hasVoice => voicePaths.isNotEmpty;

  bool get hasReminder => reminderDate != null;

  String get preview {
    final t = content.trim();
    if (t.isEmpty) {
      if (hasVoice) return 'Голосовая заметка';
      return 'Пустая заметка';
    }
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  Note copyWith({
    String? title,
    String? content,
    DateTime? reminderDate,
    bool clearReminder = false,
    int? colorIndex,
    bool? pinned,
    bool? archived,
    String? ownerKey,
    String? sectionId,
    bool clearSection = false,
    List<String>? voicePaths,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      reminderDate: clearReminder ? null : (reminderDate ?? this.reminderDate),
      colorIndex: colorIndex ?? this.colorIndex,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      ownerKey: ownerKey ?? this.ownerKey,
      sectionId: clearSection ? null : (sectionId ?? this.sectionId),
      voicePaths: voicePaths ?? this.voicePaths,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'reminderDate': reminderDate?.toIso8601String(),
        'colorIndex': colorIndex,
        'pinned': pinned,
        'archived': archived,
        'ownerKey': ownerKey,
        'sectionId': sectionId,
        'voicePaths': voicePaths,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    // Миграция: старые чек-листы → текст заметки.
    var content = (json['content'] as String?) ?? '';
    final items = json['items'] as List<dynamic>?;
    if (items != null && items.isNotEmpty && content.trim().isEmpty) {
      final lines = items.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final text = (m['text'] as String?) ?? '';
        final comment = (m['comment'] as String?) ?? '';
        return comment.trim().isEmpty ? text : '$text — $comment';
      }).where((s) => s.trim().isNotEmpty);
      content = lines.join('\n');
    }

    return Note(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      content: content,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(
        (json['updatedAt'] as String?) ?? json['createdAt'] as String,
      ),
      reminderDate: json['reminderDate'] == null
          ? null
          : DateTime.parse(json['reminderDate'] as String),
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      ownerKey: (json['ownerKey'] as String?) ?? 'guest',
      sectionId: json['sectionId'] as String?,
      voicePaths: (json['voicePaths'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'reminderDate': reminderDate?.millisecondsSinceEpoch,
        'colorIndex': colorIndex,
        'pinned': pinned,
        'archived': archived,
        'ownerKey': ownerKey,
        'sectionId': sectionId,
        'voicePaths': voicePaths,
      };

  factory Note.fromFirestore(Map<String, dynamic> json) => Note(
        id: json['id'] as String? ?? '',
        title: (json['title'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ??
              (json['createdAt'] as num?)?.toInt() ??
              0,
        ),
        reminderDate: (json['reminderDate'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['reminderDate'] as num).toInt(),
              ),
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        pinned: json['pinned'] == true,
        archived: json['archived'] == true,
        ownerKey: (json['ownerKey'] as String?) ?? 'guest',
        sectionId: json['sectionId'] as String?,
        voicePaths: (json['voicePaths'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

int _uuidSeq = 0;

String _uuid(String prefix) {
  _uuidSeq = (_uuidSeq + 1) & 0xffffff;
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = (_uuidSeq * 2654435761 & 0xffffff).toRadixString(36);
  return '${prefix}_${t}_${_uuidSeq.toRadixString(36)}$r';
}
