import 'dart:convert';

int _uuidSeq = 0;

String _uuid(String prefix) {
  _uuidSeq = (_uuidSeq + 1) & 0xffffff;
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = (_uuidSeq * 2654435761 & 0xffffff).toRadixString(36);
  return '${prefix}_${t}_${_uuidSeq.toRadixString(36)}$r';
}

/// Общее пространство (семейное / рабочее).
class FamilySpace {
  final String id;
  String name;
  int colorIndex;
  final String createdBy;
  final DateTime createdAt;
  DateTime updatedAt;

  FamilySpace({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.colorIndex = 0,
  });

  factory FamilySpace.create({
    required String name,
    required String createdBy,
    int colorIndex = 0,
  }) {
    final now = DateTime.now();
    return FamilySpace(
      id: _uuid('fs'),
      name: name,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
      colorIndex: colorIndex,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorIndex': colorIndex,
        'createdBy': createdBy,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toFirestore() => toMap();

  factory FamilySpace.fromMap(Map<String, dynamic> json) => FamilySpace(
        id: json['id'] as String? ?? '',
        name: (json['name'] as String?) ?? '',
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        createdBy: (json['createdBy'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ??
              (json['createdAt'] as num?)?.toInt() ??
              0,
        ),
      );

  static FamilySpace fromFirestore(Map<String, dynamic> json) =>
      FamilySpace.fromMap(json);
}

/// Участник пространства.
class FamilyMember {
  final String uid;
  final String email;
  String displayName;
  String firstName;
  String lastName;
  String role; // owner | member
  final DateTime joinedAt;

  FamilyMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.firstName = '',
    this.lastName = '',
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'firstName': firstName,
        'lastName': lastName,
        'role': role,
        'joinedAt': joinedAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toFirestore() => toMap();

  factory FamilyMember.fromMap(Map<String, dynamic> json) => FamilyMember(
        uid: json['uid'] as String? ?? '',
        email: (json['email'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        firstName: (json['firstName'] as String?) ?? '',
        lastName: (json['lastName'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'member',
        joinedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['joinedAt'] as num?)?.toInt() ?? 0,
        ),
      );

  static FamilyMember fromFirestore(Map<String, dynamic> json) =>
      FamilyMember.fromMap(json);
}

/// Имя участника из локального кэша members (для уведомлений о задачах).
String? familyMemberDisplayName(String? membersJsonRaw, String uid) {
  if (membersJsonRaw == null || membersJsonRaw.isEmpty) return null;
  try {
    for (final e in jsonDecode(membersJsonRaw) as List<dynamic>) {
      final m = FamilyMember.fromMap(Map<String, dynamic>.from(e as Map));
      if (m.uid != uid) continue;
      final name = m.displayName.trim();
      if (name.isNotEmpty) return name;
      final mail = m.email.trim();
      return mail.isEmpty ? null : mail.split('@').first;
    }
  } catch (_) {}
  return null;
}

/// Совместная заметка-задача с чекбоксом и напоминанием.
class FamilyNote {
  final String id;
  String title;
  String content;
  bool done;
  String? doneBy;
  DateTime? doneAt;
  DateTime? reminderDate;
  String? assigneeUid;
  final String createdBy;
  String updatedBy;
  final DateTime createdAt;
  DateTime updatedAt;

  FamilyNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    this.done = false,
    this.doneBy,
    this.doneAt,
    this.reminderDate,
    this.assigneeUid,
  });

  factory FamilyNote.create({
    required String title,
    required String content,
    required String ownerUid,
    DateTime? reminderDate,
    String? assigneeUid,
  }) {
    final now = DateTime.now();
    return FamilyNote(
      id: _uuid('fn'),
      title: title,
      content: content,
      createdBy: ownerUid,
      updatedBy: ownerUid,
      createdAt: now,
      updatedAt: now,
      reminderDate: reminderDate,
      assigneeUid: assigneeUid,
    );
  }

  FamilyNote copyWith({
    String? title,
    String? content,
    bool? done,
    String? doneBy,
    DateTime? doneAt,
    DateTime? reminderDate,
    bool clearReminder = false,
    String? assigneeUid,
    bool clearAssignee = false,
    String? updatedBy,
  }) {
    return FamilyNote(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      done: done ?? this.done,
      doneBy: doneBy ?? this.doneBy,
      doneAt: doneAt ?? this.doneAt,
      reminderDate:
          clearReminder ? null : (reminderDate ?? this.reminderDate),
      assigneeUid: clearAssignee ? null : (assigneeUid ?? this.assigneeUid),
      createdBy: createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'done': done,
        'doneBy': doneBy,
        'doneAt': doneAt?.millisecondsSinceEpoch,
        'reminderDate': reminderDate?.millisecondsSinceEpoch,
        'assigneeUid': assigneeUid,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toFirestore() => toMap();

  factory FamilyNote.fromMap(Map<String, dynamic> json) => FamilyNote(
        id: json['id'] as String? ?? '',
        title: (json['title'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
        done: json['done'] == true,
        doneBy: json['doneBy'] as String?,
        doneAt: (json['doneAt'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['doneAt'] as num).toInt()),
        reminderDate: (json['reminderDate'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['reminderDate'] as num).toInt()),
        assigneeUid: json['assigneeUid'] as String?,
        createdBy: (json['createdBy'] as String?) ?? '',
        updatedBy: (json['updatedBy'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ??
              (json['createdAt'] as num?)?.toInt() ??
              0,
        ),
      );

  static FamilyNote fromFirestore(Map<String, dynamic> json) =>
      FamilyNote.fromMap(json);
}

/// Сообщение в чате пространства.
class FamilyMessage {
  final String id;
  final String text;
  final String senderUid;
  final String senderEmail;
  final String senderName;
  final DateTime createdAt;

  FamilyMessage({
    required this.id,
    required this.text,
    required this.senderUid,
    required this.senderEmail,
    required this.senderName,
    required this.createdAt,
  });

  factory FamilyMessage.create({
    required String text,
    required String senderUid,
    required String senderEmail,
    required String senderName,
  }) {
    return FamilyMessage(
      id: _uuid('fm'),
      text: text,
      senderUid: senderUid,
      senderEmail: senderEmail,
      senderName: senderName,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'senderUid': senderUid,
        'senderEmail': senderEmail,
        'senderName': senderName,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toFirestore() => toMap();

  factory FamilyMessage.fromMap(Map<String, dynamic> json) => FamilyMessage(
        id: json['id'] as String? ?? '',
        text: (json['text'] as String?) ?? '',
        senderUid: (json['senderUid'] as String?) ?? '',
        senderEmail: (json['senderEmail'] as String?) ?? '',
        senderName: (json['senderName'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );

  static FamilyMessage fromFirestore(Map<String, dynamic> json) =>
      FamilyMessage.fromMap(json);
}

/// Приглашение в пространство (doc id = email приглашённого).
class FamilyInvite {
  final String email;
  final String spaceId;
  final String spaceName;
  final String invitedBy;
  final String status; // pending | accepted | declined
  final DateTime createdAt;
  final String displayName;

  FamilyInvite({
    required this.email,
    required this.spaceId,
    required this.spaceName,
    required this.invitedBy,
    required this.status,
    required this.createdAt,
    this.displayName = '',
  });

  Map<String, dynamic> toMap() => {
        'email': email,
        'spaceId': spaceId,
        'spaceName': spaceName,
        'invitedBy': invitedBy,
        'status': status,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'displayName': displayName,
      };

  Map<String, dynamic> toFirestore() => toMap();

  factory FamilyInvite.fromMap(Map<String, dynamic> json) => FamilyInvite(
        email: (json['email'] as String?) ?? '',
        spaceId: (json['spaceId'] as String?) ?? '',
        spaceName: (json['spaceName'] as String?) ?? '',
        invitedBy: (json['invitedBy'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        displayName: (json['displayName'] as String?) ?? '',
      );

  static FamilyInvite fromFirestore(Map<String, dynamic> json) =>
      FamilyInvite.fromMap(json);
}
