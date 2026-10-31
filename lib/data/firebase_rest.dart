import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models/note.dart';
import 'models/standalone_reminder.dart';

/// Firebase поверх REST API.
///
/// Нужен для платформ без официального SDK (Windows/desktop):
/// `firebase_core` там не поддерживается, а синхронизировать заметки
/// с телефоном всё равно надо. Использует те же Identity Toolkit и
/// Firestore REST, что и мобильный SDK, — данные лежат в одном месте.
class FirebaseRest {
  FirebaseRest._();
  static final FirebaseRest instance = FirebaseRest._();

  /// Из android/app/google-services.json (общий для проекта).
  static const apiKey = 'AIzaSyBe9-cZ7S7RURsTAlidsIyN0DQafmNMSoA';
  static const projectId = 'my-notes-71034';

  static const _identity = 'https://identitytoolkit.googleapis.com/v1';
  static const _secureToken = 'https://securetoken.googleapis.com/v1';
  static const _firestore =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  String? idToken;
  String? refreshToken;
  String? uid;
  String? email;
  DateTime? _expiresAt;

  /// Сессия считается живой, если есть uid и refreshToken.
  /// idToken подтягивается лениво через [_ensureToken].
  bool get isSignedIn => uid != null && refreshToken != null;

  /// Публичная проверка/обновление сессии (вызывать после восстановления).
  Future<void> refreshSession() => _ensureToken();

  // ── Авторизация ───────────────────────────────────────────

  Future<Map<String, dynamic>> signIn(String email, String password) =>
      _auth('accounts:signInWithPassword', {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      });

  Future<Map<String, dynamic>> register(String email, String password) =>
      _auth('accounts:signUp', {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      });

  Future<void> sendPasswordReset(String email) async {
    await _auth('accounts:sendOobCode', {
      'requestType': 'PASSWORD_RESET',
      'email': email,
    });
  }

  Future<Map<String, dynamic>> _auth(
    String method,
    Map<String, dynamic> body,
  ) async {
    final resp = await http.post(
      Uri.parse('$_identity/$method?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = _decode(resp);
    if (resp.statusCode != 200) {
      throw RestAuthException(_mapAuthError(data['error']));
    }
    idToken = data['idToken'] as String;
    refreshToken = data['refreshToken'] as String;
    uid = data['localId'] as String;
    email = data['email'] as String? ?? email;
    _expiresAt = DateTime.now().add(
      Duration(seconds: int.tryParse('${data['expiresIn']}') ?? 3600),
    );
    return data;
  }

  /// Обновляет idToken, если его нет или срок истёк.
  Future<void> _ensureToken() async {
    if (refreshToken == null) {
      throw const RestAuthException('Нет сессии');
    }
    if (idToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(
          _expiresAt!.subtract(const Duration(minutes: 5)),
        )) {
      return;
    }
    final resp = await http.post(
      Uri.parse('$_secureToken/token?key=$apiKey'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken!},
    );
    final data = _decode(resp);
    if (resp.statusCode != 200) {
      throw const RestAuthException('Сессия истекла — войдите заново');
    }
    idToken = data['id_token'] as String;
    refreshToken = data['refresh_token'] as String;
    _expiresAt = DateTime.now().add(
      Duration(seconds: int.tryParse('${data['expires_in']}') ?? 3600),
    );
  }

  Future<void> signOut() async {
    idToken = null;
    refreshToken = null;
    uid = null;
    email = null;
    _expiresAt = null;
  }

  // ── Firestore ─────────────────────────────────────────────

  String _docPath(String collection, [String? id]) =>
      id == null
          ? '$_firestore/users/$uid/$collection'
          : '$_firestore/users/$uid/$collection/$id';

  /// Все документы коллекции.
  Future<List<Map<String, dynamic>>> fetchAll(String collection) async {
    await _ensureToken();
    final out = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.parse(_docPath(collection)).replace(
        queryParameters: {
          'pageSize': '300',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $idToken'},
      );
      final data = _decode(resp);
      if (resp.statusCode != 200) {
        throw RestAuthException(_mapAuthError(data['error']));
      }
      for (final d in (data['documents'] as List<dynamic>? ?? [])) {
        final doc = Map<String, dynamic>.from(d as Map);
        out.add(_fromFirestoreDoc(doc));
      }
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);
    return out;
  }

  /// Создаёт/обновляет документ.
  Future<void> upsert(String collection, String id, Map<String, dynamic> f) async {
    await _ensureToken();
    final resp = await http.patch(
      Uri.parse(_docPath(collection, id)),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': _toFirestoreFields(f)}),
    );
    if (resp.statusCode != 200) {
      final data = _decode(resp);
      throw RestAuthException(_mapAuthError(data['error']));
    }
  }

  Future<void> delete(String collection, String id) async {
    await _ensureToken();
    final resp = await http.delete(
      Uri.parse(_docPath(collection, id)),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (resp.statusCode != 200 && resp.statusCode != 404) {
      final data = _decode(resp);
      throw RestAuthException(_mapAuthError(data['error']));
    }
  }

  // ── Общие коллекции (family_spaces, mailboxes) ────────────

  /// Произвольный относительный путь от documents/ (без users/{uid}).
  String _relPath(String rel, [String? id]) =>
      id == null ? '$_firestore/$rel' : '$_firestore/$rel/$id';

  Future<List<Map<String, dynamic>>> fetchPath(String rel) async {
    await _ensureToken();
    final out = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.parse(_relPath(rel)).replace(
        queryParameters: {
          'pageSize': '300',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $idToken'},
      );
      final data = _decode(resp);
      if (resp.statusCode != 200) {
        throw RestAuthException(_mapAuthError(data['error']));
      }
      for (final d in (data['documents'] as List<dynamic>? ?? [])) {
        final doc = Map<String, dynamic>.from(d as Map);
        out.add(_fromFirestoreDoc(doc));
      }
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);
    return out;
  }

  /// Один документ по относительному пути (без users/{uid}).
  Future<Map<String, dynamic>?> getDoc(String rel) async {
    await _ensureToken();
    final resp = await http.get(
      Uri.parse(_relPath(rel)),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (resp.statusCode == 404) return null;
    final data = _decode(resp);
    if (resp.statusCode != 200) {
      throw RestAuthException(_mapAuthError(data['error']));
    }
    if (!data.containsKey('fields')) return null;
    return _fromFirestoreDoc(data);
  }

  Future<void> upsertPath(String rel, String id, Map<String, dynamic> f) async {
    await _ensureToken();
    final resp = await http.patch(
      Uri.parse(_relPath(rel, id)),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': _toFirestoreFields(f)}),
    );
    if (resp.statusCode != 200) {
      final data = _decode(resp);
      throw RestAuthException(_mapAuthError(data['error']));
    }
  }

  Future<void> deletePath(String rel, String id) async {
    await _ensureToken();
    final resp = await http.delete(
      Uri.parse(_relPath(rel, id)),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (resp.statusCode != 200 && resp.statusCode != 404) {
      final data = _decode(resp);
      throw RestAuthException(_mapAuthError(data['error']));
    }
  }

  // ── Типы Firestore ────────────────────────────────────────

  static Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> m) {
    return m.map((k, v) => MapEntry(k, _toValue(v)));
  }

  static dynamic _toValue(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is List) return {
          'arrayValue': {'values': v.map(_toValue).toList()},
        };
    return {'stringValue': v.toString()};
  }

  static Map<String, dynamic> _fromFirestoreDoc(Map<String, dynamic> doc) {
    final fields = Map<String, dynamic>.from(doc['fields'] as Map? ?? {});
    return fields.map((k, v) => MapEntry(k, _fromValue(v)));
  }

  static dynamic _fromValue(dynamic v) {
    final m = Map<String, dynamic>.from(v as Map);
    if (m.containsKey('nullValue')) return null;
    if (m.containsKey('booleanValue')) return m['booleanValue'] as bool;
    if (m.containsKey('integerValue')) {
      return int.tryParse('${m['integerValue']}') ?? 0;
    }
    if (m.containsKey('doubleValue')) return m['doubleValue'];
    if (m.containsKey('stringValue')) return m['stringValue'];
    if (m.containsKey('arrayValue')) {
      final values = (m['arrayValue']['values'] as List<dynamic>? ?? []);
      return values.map(_fromValue).toList();
    }
    return null;
  }

  static Map<String, dynamic> _decode(http.Response resp) {
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(resp.bodyBytes)) as Map);
    } catch (_) {
      return {};
    }
  }

  static String _mapAuthError(dynamic error) {
    if (error == null) {
      return 'Не удалось выполнить запрос. Проверьте соединение.';
    }
    final code = error is Map ? '${error['message']}' : '$error';
    switch (code) {
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'INVALID_PASSWORD':
        return 'Неверный email или пароль';
      case 'EMAIL_EXISTS':
        return 'Этот email уже зарегистрирован';
      case 'INVALID_EMAIL':
        return 'Некорректный email';
      case 'WEAK_PASSWORD : Password should be at least 6 characters':
        return 'Слишком простой пароль (мин. 6 символов)';
      case 'USER_DISABLED':
        return 'Аккаунт заблокирован';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Слишком много попыток. Попробуйте позже';
      case 'OPERATION_NOT_ALLOWED':
        return 'Вход по email/password отключён в проекте Firebase';
      default:
        if (code.contains('NETWORK')) return 'Нет соединения с интернетом';
        return 'Ошибка: $code';
    }
  }
}

/// Ошибка авторизации/сети Firebase REST.
class RestAuthException implements Exception {
  final String message;
  const RestAuthException(this.message);
  @override
  String toString() => message;
}

// ── Удобные обёртки для моделей ──────────────────────────────

extension RestNotes on FirebaseRest {
  Future<List<Note>> pullNotes() async {
    final raw = await fetchAll('notes');
    return raw.map((m) => Note.fromFirestore(_cast(m))).toList();
  }

  Future<List<NoteSection>> pullNoteSections() async {
    final raw = await fetchAll('sections');
    return raw.map((m) => NoteSection.fromFirestore(_cast(m))).toList();
  }

  Future<List<StandaloneReminder>> pullReminders() async {
    final raw = await fetchAll('reminders');
    return raw.map((m) => StandaloneReminder.fromFirestore(_cast(m))).toList();
  }

  Future<List<ReminderSection>> pullReminderSections() async {
    final raw = await fetchAll('reminder_sections');
    return raw.map((m) => ReminderSection.fromFirestore(_cast(m))).toList();
  }

  Future<void> pushNote(Note n) =>
      upsert('notes', n.id, n.toFirestore());
  Future<void> pushNoteSection(NoteSection s) =>
      upsert('sections', s.id, s.toFirestore());
  Future<void> pushReminder(StandaloneReminder r) =>
      upsert('reminders', r.id, r.toFirestore());
  Future<void> pushReminderSection(ReminderSection s) =>
      upsert('reminder_sections', s.id, s.toFirestore());

  static Map<String, dynamic> _cast(Map<String, dynamic> m) =>
      m.map((k, v) => MapEntry(k, v));
}

// ── Семейные пространства поверх общих путей ───────────────

extension RestFamily on FirebaseRest {
  static const String familyPrefix = 'family_spaces';

  String spacePath(String spaceId, String collection, [String? id]) {
    final rel = '$familyPrefix/$spaceId/$collection';
    return id == null ? rel : '$rel/$id';
  }

  Future<List<Map<String, dynamic>>> pullSpaceCollection(
    String spaceId,
    String collection,
  ) =>
      fetchPath('$familyPrefix/$spaceId/$collection');

  Future<void> pushSpaceDoc(
    String spaceId,
    String collection,
    String id,
    Map<String, dynamic> data,
  ) =>
      upsertPath('$familyPrefix/$spaceId/$collection', id, data);

  Future<void> removeSpaceDoc(
    String spaceId,
    String collection,
    String id,
  ) =>
      deletePath('$familyPrefix/$spaceId/$collection', id);

  /// Приглашения в почтовом ящике пользователя (doc id = email).
  Future<List<Map<String, dynamic>>> pullMailboxInvites(String email) =>
      fetchPath('mailboxes/$email/invites');

  Future<void> pushMailboxInvite(
    String email,
    String spaceId,
    Map<String, dynamic> data,
  ) =>
      upsertPath('mailboxes/$email/invites', spaceId, data);

  Future<void> removeMailboxInvite(String email, String spaceId) =>
      deletePath('mailboxes/$email/invites', spaceId);
}

/// REST-вариант mapAuthError для слоёв, которым нужен текст ошибки.
String restAuthMessage(Object e) =>
    e is RestAuthException ? e.message : 'Не удалось выполнить операцию';

/// [debugPrint] только в debug — чтобы не засорять лог релиза.
void restLog(String message) {
  if (kDebugMode) debugPrint(message);
}
