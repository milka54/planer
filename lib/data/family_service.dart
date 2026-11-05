import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'firebase_rest.dart';
import 'models/family_space.dart';
import 'notifications.dart';

/// Семейные / общие заметки: пространства, участники, задачи, чат.
///
/// Данные лежат в `family_spaces/{spaceId}/...` (общие для всех участников)
/// и в `mailboxes/{email}/invites` (входящие приглашения).
/// Local-first: кэш в SharedPreferences + репликация в Firestore.
class FamilyService {
  FamilyService._();
  static final FamilyService instance = FamilyService._();

  final ValueNotifier<List<FamilySpace>> spaces =
      ValueNotifier<List<FamilySpace>>([]);
  final ValueNotifier<List<FamilyInvite>> invites =
      ValueNotifier<List<FamilyInvite>>([]);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// Пространство, чат которого сейчас открыт (не уведомляем о нём).
  static String? activeChatSpaceId;

  /// Приложение на переднем плане (см. HomeShell.didChangeAppLifecycleState).
  /// Подавлять уведомления открытого чата можно только пока пользователь
  /// реально смотрит в экран — свёрнутое приложение обязано уведомлять.
  static bool appInForeground = true;

  /// Счётчики непрочитанных сообщений по пространствам.
  final ValueNotifier<Map<String, int>> unread =
      ValueNotifier<Map<String, int>>({});

  static const _kSpaces = 'family_spaces_cache_v1';
  static const _kUnreadPrefix = 'family_unread_v1_';
  static const _kLastMsgPrefix = 'family_lastmsg_v1_';
  static const _kMembersPrefix = 'family_members_v1_';
  static const _kNotesPrefix = 'family_notes_v1_';
  static const _kMsgsPrefix = 'family_msgs_v1_';
  static const _kInvites = 'family_invites_cache_v1';

  Future<SharedPreferences> _p() => SharedPreferences.getInstance();

  String? get _uid => AuthService.instance.userKey.value;
  String? get _email => AuthService.instance.userEmail.value;
  bool get _synced =>
      !AuthService.instance.isGuest.value &&
      _uid != null &&
      _uid != 'guest' &&
      _email != null;

  // ── Фоновый опрос и непрочитанные ─────────────────────────

  Timer? _bgTimer;

  /// Запускает периодический опрос всех пространств (идёт из HomeShell).
  void startBackgroundPolling(
      {Duration interval = const Duration(seconds: 20)}) {
    _bgTimer?.cancel();
    _bgTimer = Timer.periodic(interval, (_) => pollAllSpaces());
    unawaited(pollAllSpaces());
  }

  void stopBackgroundPolling() {
    _bgTimer?.cancel();
    _bgTimer = null;
  }

  /// Новые чужие сообщения → уведомление (если чат не открыт) + счётчик.
  Future<void> pollAllSpaces() async {
    if (!_synced) return;
    final prefs = await _p();
    for (final space in spaces.value) {
      try {
        await _pollSpaceTasks(space, prefs);
        final msgs = await messages(space.id);
        if (msgs.isEmpty) continue;
        final lastKey = '$_kLastMsgPrefix${space.id}';
        final lastSeenId = prefs.getString(lastKey);
        final lastMsg = msgs.last;
        if (lastSeenId == lastMsg.id) continue;

        var newCount = 0;
        final myUid = _uid;
        for (final m in msgs.reversed) {
          if (m.id == lastSeenId) break;
          if (m.senderUid != myUid) newCount++;
        }
        await prefs.setString(lastKey, lastMsg.id);
        if (newCount == 0) continue;

        // Смотрим в этот чат на переднем плане — сообщение видно в списке.
        // Свёрнутое приложение обязано уведомлять (и считать непрочитанные).
        if (!(appInForeground && activeChatSpaceId == space.id)) {
          final lastForeign = msgs.lastWhere(
            (m) => m.senderUid != myUid,
            orElse: () => lastMsg,
          );
          await NotificationService.instance.showSpaceChatMessage(
            spaceId: space.id,
            spaceName: space.name,
            senderName: lastForeign.senderName,
            text: lastForeign.text,
          );
          final cur = Map<String, int>.from(unread.value);
          cur[space.id] = (cur[space.id] ?? 0) + newCount;
          unread.value = cur;
          await prefs.setString(
              '$_kUnreadPrefix${space.id}', '${cur[space.id]}');
        }
      } catch (e) {
        debugPrint('family pollAllSpaces(${space.id}): $e');
      }
    }
  }

  /// Помечает пространство прочитанным.
  Future<void> markRead(String spaceId) async {
    if ((unread.value[spaceId] ?? 0) == 0) return;
    final prefs = await _p();
    final cur = Map<String, int>.from(unread.value)..remove(spaceId);
    unread.value = cur;
    await prefs.remove('$_kUnreadPrefix$spaceId');
    try {
      final msgs = await messages(spaceId);
      if (msgs.isNotEmpty) {
        await prefs.setString('$_kLastMsgPrefix$spaceId', msgs.last.id);
      }
    } catch (_) {}
  }

  /// Восстанавливает счётчики из хранилища при старте.
  Future<void> loadUnread() async {
    final prefs = await _p();
    final map = <String, int>{};
    for (final s in spaces.value) {
      final v = prefs.getString('$_kUnreadPrefix${s.id}');
      if (v != null) {
        final n = int.tryParse(v) ?? 0;
        if (n > 0) map[s.id] = n;
      }
    }
    unread.value = map;
  }

  // ── Доступ к облаку (SDK или REST) ────────────────────────

  bool get _useRest {
    try {
      fs.FirebaseFirestore.instance;
      return false;
    } catch (_) {
      return FirebaseRest.instance.isSignedIn;
    }
  }

  fs.CollectionReference<Map<String, dynamic>> _fsCol(
    String spaceId,
    String collection,
  ) =>
      fs.FirebaseFirestore.instance
          .collection('family_spaces')
          .doc(spaceId)
          .collection(collection);

  Future<List<Map<String, dynamic>>> _pull(
    String spaceId,
    String collection,
  ) async {
    if (_useRest) {
      return FirebaseRest.instance.pullSpaceCollection(spaceId, collection);
    }
    final snap = await _fsCol(spaceId, collection).get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = data['id'] ?? d.id;
      return data;
    }).toList();
  }

  Future<void> _push(
    String spaceId,
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (_useRest) {
      await FirebaseRest.instance.pushSpaceDoc(spaceId, collection, id, data);
      return;
    }
    await _fsCol(spaceId, collection).doc(id).set(data);
  }

  Future<void> _remove(String spaceId, String collection, String id) async {
    if (_useRest) {
      await FirebaseRest.instance.removeSpaceDoc(spaceId, collection, id);
      return;
    }
    await _fsCol(spaceId, collection).doc(id).delete();
  }

  /// Пишет пространство в личный индекс вступлений — без него пространство,
  /// в которое вошли по коду-ссылке, не появится в списке.
  Future<void> _indexJoinedSpace(String spaceId, String name) async {
    if (!_synced) return;
    try {
      final data = {
        'spaceId': spaceId,
        'name': name,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
      };
      if (_useRest) {
        await FirebaseRest.instance
            .upsertPath('users/$_uid/joined_spaces', spaceId, data);
      } else {
        await fs.FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('joined_spaces')
            .doc(spaceId)
            .set(data);
      }
    } catch (e) {
      debugPrint('family indexJoinedSpace: $e');
    }
  }

  Future<void> _unindexJoinedSpace(String spaceId) async {
    if (!_synced) return;
    try {
      if (_useRest) {
        await FirebaseRest.instance
            .deletePath('users/$_uid/joined_spaces', spaceId);
      } else {
        await fs.FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('joined_spaces')
            .doc(spaceId)
            .delete();
      }
    } catch (e) {
      debugPrint('family unindexJoinedSpace: $e');
    }
  }

  /// Полная очистка состояния (выход из аккаунта / смена пользователя).
  /// Сбрасывает пространства, приглашения, непрочитанные и локальный кэш.
  Future<void> clear() async {
    stopBackgroundPolling();
    spaces.value = [];
    invites.value = [];
    unread.value = {};
    activeChatSpaceId = null;
    final prefs = await _p();
    await prefs.remove(_kSpaces);
    await prefs.remove(_kInvites);
    // Кэши пространств (members/notes/msgs/unread/lastmsg) удаляем по префиксу.
    final keys = prefs.getKeys().toList();
    for (final k in keys) {
      if (k.startsWith(_kUnreadPrefix) ||
          k.startsWith(_kLastMsgPrefix) ||
          k.startsWith(_kMembersPrefix) ||
          k.startsWith(_kNotesPrefix) ||
          k.startsWith(_kMsgsPrefix) ||
          k.startsWith('family_knowntasks_v1_') ||
          k.startsWith('space_rem_fired_v1_')) {
        await prefs.remove(k);
      }
    }
  }

  // ── Загрузка ──────────────────────────────────────────────

  Future<void> load() async {
    loading.value = true;
    try {
      final prefs = await _p();
      final localSpaces = _decodeList(prefs.getString(_kSpaces))
          .map(FamilySpace.fromMap)
          .toList();

      if (_synced) {
        // Приглашения — из почтового ящика.
        List<FamilyInvite> remoteInvites = [];
        try {
          if (_useRest) {
            final raw = await FirebaseRest.instance.pullMailboxInvites(_email!);
            remoteInvites =
                raw.map(FamilyInvite.fromMap).toList();
          } else {
            final snap = await fs.FirebaseFirestore.instance
                .collection('mailboxes')
                .doc(_email)
                .collection('invites')
                .get();
            remoteInvites = snap.docs.map((d) {
              final data = d.data();
              data['email'] = data['email'] ?? _email;
              return FamilyInvite.fromMap(data);
            }).toList();
          }
        } catch (e) {
          debugPrint('family invites pull: $e');
        }

        // Собственные пространства: кэш + индекс вступлений + email-приглашения.
        final merged = <String, FamilySpace>{
          for (final s in localSpaces) s.id: s,
        };
        // Индекс вступлений в профиле — пространства, куда вступил по
        // коду-ссылке или по приглашению (иначе их никто не найдёт).
        List<Map<String, dynamic>> joinedIndex = [];
        try {
          if (_useRest) {
            joinedIndex = await FirebaseRest.instance
                .fetchPath('users/$_uid/joined_spaces');
          } else {
            final snap = await fs.FirebaseFirestore.instance
                .collection('users')
                .doc(_uid)
                .collection('joined_spaces')
                .get();
            joinedIndex = snap.docs.map((d) {
              final data = d.data();
              data['id'] = data['id'] ?? d.id;
              return data;
            }).toList();
          }
        } catch (e) {
          debugPrint('family joined index pull: $e');
        }

        final spaceIds = <String>{
          ...merged.keys,
          for (final j in joinedIndex) '${j['spaceId'] ?? j['id']}',
          for (final inv in remoteInvites.where((i) => i.status == 'accepted'))
            inv.spaceId,
        };
        for (final id in spaceIds) {
          if (id.isEmpty) continue;
          try {
            final space = await _pullSpace(id);
            if (space != null) {
              merged[space.id] = space;
              // Чиним индекс, если пространство нашлось, а записи нет.
              if (!joinedIndex.any((j) => (j['spaceId'] ?? j['id']) == space.id)) {
                await _indexJoinedSpace(space.id, space.name);
              }
            }
          } catch (e) {
            debugPrint('family space pull($id): $e');
          }
        }

        final list = merged.values.toList();
        await prefs.setString(
            _kSpaces, jsonEncode(list.map((s) => s.toMap()).toList()));
        spaces.value = list;
        invites.value =
            remoteInvites.where((i) => i.status == 'pending').toList();
        await prefs.setString(_kInvites,
            jsonEncode(remoteInvites.map((i) => i.toMap()).toList()));
      } else {
        // Гость — не показываем чужие пространства.
        // Очищаем кэш, если он остался от предыдущего аккаунта.
        if (localSpaces.isNotEmpty) {
          await clear();
        }
        spaces.value = [];
        invites.value = [];
      }
    } finally {
      loading.value = false;
    }
  }

  Future<FamilySpace?> _pullSpace(String spaceId) async {
    if (_useRest) {
      final m = await FirebaseRest.instance.getDoc('family_spaces/$spaceId');
      if (m == null) return null;
      final data = Map<String, dynamic>.from(m);
      data['id'] = data['id'] ?? spaceId;
      return FamilySpace.fromMap(data);
    }
    final doc = await fs.FirebaseFirestore.instance
        .collection('family_spaces')
        .doc(spaceId)
        .get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = data['id'] ?? spaceId;
    return FamilySpace.fromMap(data);
  }

  // ── Пространства ──────────────────────────────────────────

  Future<FamilySpace> createSpace({required String name}) async {
    final uid = _uid!;
    final space = FamilySpace.create(name: name, createdBy: uid);
    spaces.value = [...spaces.value, space];
    await _persistSpaces();
    if (_synced) {
      // Документ пространства — в корне family_spaces/{id}.
      if (_useRest) {
        await FirebaseRest.instance
            .upsertPath('family_spaces', space.id, space.toFirestore());
      } else {
        await fs.FirebaseFirestore.instance
            .collection('family_spaces')
            .doc(space.id)
            .set(space.toFirestore());
      }
      final owner = FamilyMember(
        uid: uid,
        email: _email!,
        displayName: _email!.split('@').first,
        role: 'owner',
        joinedAt: DateTime.now(),
      );
      await _push(space.id, 'members', uid, owner.toFirestore());
    }
    await saveMember(space.id, FamilyMember(
      uid: uid,
      email: _email ?? '',
      displayName: (_email ?? '').split('@').first,
      role: 'owner',
      joinedAt: DateTime.now(),
    ));
    await _indexJoinedSpace(space.id, space.name);
    return space;
  }

  Future<void> deleteSpace(String spaceId) async {
    // Удалить пространство может только его создатель (см. firestore.rules).
    final space = spaces.value.where((s) => s.id == spaceId).firstOrNull;
    if (space != null && space.createdBy != _uid) {
      throw const RestAuthException(
        'Удалить пространство может только тот, кто его создал',
      );
    }
    spaces.value = spaces.value.where((s) => s.id != spaceId).toList();
    await _persistSpaces();
    await _unindexJoinedSpace(spaceId);
    if (_synced) {
      try {
        if (_useRest) {
          await FirebaseRest.instance.deletePath('family_spaces', spaceId);
        } else {
          await fs.FirebaseFirestore.instance
              .collection('family_spaces')
              .doc(spaceId)
              .delete();
        }
      } catch (e) {
        debugPrint('family deleteSpace: $e');
      }
    }
    final prefs = await _p();
    await prefs.remove('$_kMembersPrefix$spaceId');
    await prefs.remove('$_kNotesPrefix$spaceId');
    await prefs.remove('$_kMsgsPrefix$spaceId');
  }

  // ── Участники ─────────────────────────────────────────────

  List<FamilyMember> _membersCache = [];
  String _membersSpaceId = '';

  Future<List<FamilyMember>> members(String spaceId, {bool force = false}) async {
    if (!force && _membersSpaceId == spaceId && _membersCache.isNotEmpty) {
      return _membersCache;
    }
    final prefs = await _p();
    var list = _decodeList(prefs.getString('$_kMembersPrefix$spaceId'))
        .map(FamilyMember.fromMap)
        .toList();
    if (_synced) {
      try {
        final remote = await _pull(spaceId, 'members');
        final remoteList = remote.map(FamilyMember.fromMap).toList();
        if (remoteList.isNotEmpty) {
          list = remoteList;
          await prefs.setString('$_kMembersPrefix$spaceId',
              jsonEncode(list.map((m) => m.toMap()).toList()));
        }
      } catch (e) {
        debugPrint('family members pull: $e');
      }
    }
    _membersCache = list;
    _membersSpaceId = spaceId;
    return list;
  }

  Future<void> saveMember(
    String spaceId,
    FamilyMember member, {
    String? joinToken,
  }) async {
    final prefs = await _p();
    final list = await members(spaceId)
      ..removeWhere((m) => m.uid == member.uid)
      ..add(member);
    await prefs.setString('$_kMembersPrefix$spaceId',
        jsonEncode(list.map((m) => m.toMap()).toList()));
    _membersCache = list;
    if (_synced) {
      try {
        final data = member.toFirestore();
        // Токен нужен ТОЛЬКО при первом создании карточки —
        // правила сверяют его с join_codes/{token}.
        if (joinToken != null) data['joinToken'] = joinToken;
        await _push(spaceId, 'members', member.uid, data);
      } catch (e) {
        debugPrint('family saveMember: $e');
      }
    }
  }

  /// Удаляет участника из пространства (только владелец).
  Future<void> removeMember(String spaceId, FamilyMember member) async {
    final prefs = await _p();
    final list = await members(spaceId)
      ..removeWhere((m) => m.uid == member.uid);
    await prefs.setString('$_kMembersPrefix$spaceId',
        jsonEncode(list.map((m) => m.toMap()).toList()));
    _membersCache = list;
    if (_synced) {
      try {
        await _remove(spaceId, 'members', member.uid);
        // Приглашение тоже убираем, чтобы не «всплывало» снова.
        await _remove(spaceId, 'invites', member.email);
        if (_useRest) {
          await FirebaseRest.instance
              .removeMailboxInvite(member.email, spaceId);
        } else {
          await fs.FirebaseFirestore.instance
              .collection('mailboxes')
              .doc(member.email)
              .collection('invites')
              .doc(spaceId)
              .delete();
        }
      } catch (e) {
        debugPrint('family removeMember: $e');
      }
    }
    // Если удалили себя — убираем из личного индекса вступлений.
    if (member.uid == _uid) {
      await _unindexJoinedSpace(spaceId);
    }
  }

  /// Выход пользователя из пространства: убирает свою карточку участника
  /// и пространство из личного списка. Задачи и переписка остаются.
  Future<void> leaveSpace(String spaceId) async {
    final me = (await members(spaceId))
        .where((m) => m.uid == _uid)
        .firstOrNull;
    if (me == null) return;
    // Владельцу вместо выхода доступно удаление пространства.
    if (me.role == 'owner') {
      throw const RestAuthException(
        'Вы создатель пространства — вы можете только удалить его',
      );
    }
    await removeMember(spaceId, me);
    spaces.value = spaces.value.where((s) => s.id != spaceId).toList();
    await _persistSpaces();
  }

  // ── Вступление по коду-ссылке ─────────────────────────────

  static String _newToken() {
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    // Маска, чтобы не было переполнения в отрицательное число (с минусом).
    final rnd = (DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF)
        .toRadixString(36)
        .padLeft(6, '0');
    return 'pln${ms}_$rnd';
  }

  /// Создаёт код-ссылку для вступления. Возвращает токен.
  Future<String> generateJoinCode(String spaceId) async {
    final found = spaces.value.where((s) => s.id == spaceId);
    if (found.isEmpty) {
      throw const RestAuthException(
          'Пространство не найдено — обновите его и попробуйте снова');
    }
    final space = found.first;
    final token = _newToken();
    if (_useRest) {
      await FirebaseRest.instance.upsertPath('join_codes', token, {
        'token': token,
        'spaceId': spaceId,
        'spaceName': space.name,
        'createdBy': _uid,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await fs.FirebaseFirestore.instance
          .collection('join_codes')
          .doc(token)
          .set({
        'token': token,
        'spaceId': spaceId,
        'spaceName': space.name,
        'createdBy': _uid,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    return token;
  }

  /// Достаёт токен из вставленного текста: голый токен, `planer://join/<token>`,
  /// ссылка целиком или вежливое сообщение с кодом внутри.
  static String extractJoinToken(String raw) {
    final s = raw.trim();
    final match = RegExp(r'pln[a-z0-9_-]+').firstMatch(s);
    if (match != null) return match.group(0)!;
    var token = s;
    for (final sep in ['/', '#', '?token=', ':']) {
      if (token.contains(sep)) token = token.split(sep).last.trim();
    }
    return token.trim();
  }

  /// Вступление по токену из ссылки. Возвращает название пространства.
  Future<String> joinByCode(String rawCode) async {
    if (!_synced) {
      throw const RestAuthException('Сначала войдите в аккаунт');
    }
    // Принимаем как голый токен, так и ссылку вида planer://join/<token>
    // или сообщение с кодом — токен вырезается по шаблону pln...
    final token = extractJoinToken(rawCode);
    if (token.isEmpty) {
      throw const RestAuthException('Пустой код приглашения');
    }

    Map<String, dynamic>? data;
    if (_useRest) {
      data = await FirebaseRest.instance.getDoc('join_codes/$token');
    } else {
      final doc = await fs.FirebaseFirestore.instance
          .collection('join_codes')
          .doc(token)
          .get();
      data = doc.data();
    }
    if (data == null) {
      throw const RestAuthException('Код приглашения недействителен');
    }
    final spaceId = (data['spaceId'] ?? '') as String;
    final spaceName = (data['spaceName'] ?? '') as String;
    if (spaceId.isEmpty) {
      throw const RestAuthException('Код приглашения недействителен');
    }

    // Уже участник?
    if (spaces.value.any((s) => s.id == spaceId)) {
      return spaceName;
    }

    final member = FamilyMember(
      uid: _uid!,
      email: _email!,
      displayName: _email!.split('@').first,
      role: 'member',
      joinedAt: DateTime.now(),
    );
    // Токен передаём в карточке участника — правила сверяют его
    // с join_codes/{token}. Без него вступление запрещено.
    await saveMember(spaceId, member, joinToken: token);
    // Обязательно в индекс вступлений — иначе load() не найдёт пространство.
    await _indexJoinedSpace(spaceId, spaceName);
    await load();
    return spaceName;
  }

  /// Удаляет код-ссылку (владелец отзывает).
  Future<void> revokeJoinCode(String token) async {
    if (_useRest) {
      await FirebaseRest.instance.deletePath('join_codes', token);
    } else {
      await fs.FirebaseFirestore.instance
          .collection('join_codes')
          .doc(token)
          .delete();
    }
  }

  // ── Приглашения ───────────────────────────────────────────

  Future<void> invite({
    required String spaceId,
    required String email,
    String displayName = '',
  }) async {
    final space = spaces.value.firstWhere((s) => s.id == spaceId);
    final invite = FamilyInvite(
      email: email.trim(),
      spaceId: spaceId,
      spaceName: space.name,
      invitedBy: _email ?? '',
      status: 'pending',
      createdAt: DateTime.now(),
      displayName: displayName.trim(),
    );
    if (!_synced) {
      throw const RestAuthException('Войдите в аккаунт, чтобы приглашать');
    }
    // В пространство — чтобы владелец видел список приглашений.
    await _push(spaceId, 'invites', invite.email, invite.toFirestore());
    // В почтовый ящик приглашённого.
    if (_useRest) {
      await FirebaseRest.instance
          .pushMailboxInvite(invite.email, spaceId, invite.toFirestore());
    } else {
      await fs.FirebaseFirestore.instance
          .collection('mailboxes')
          .doc(invite.email)
          .collection('invites')
          .doc(spaceId)
          .set(invite.toFirestore());
    }
  }

  Future<void> acceptInvite(FamilyInvite invite) async {
    final uid = _uid!;
    final member = FamilyMember(
      uid: uid,
      email: invite.email,
      displayName: invite.displayName.isNotEmpty
          ? invite.displayName
          : invite.email.split('@').first,
      role: 'member',
      joinedAt: DateTime.now(),
    );
    await saveMember(invite.spaceId, member);
    await _indexJoinedSpace(invite.spaceId, invite.spaceName);
    final accepted = FamilyInvite(
      email: invite.email,
      spaceId: invite.spaceId,
      spaceName: invite.spaceName,
      invitedBy: invite.invitedBy,
      status: 'accepted',
      createdAt: invite.createdAt,
    );
    if (_synced) {
      try {
        await _push(invite.spaceId, 'invites', invite.email, accepted.toFirestore());
        if (_useRest) {
          await FirebaseRest.instance
              .pushMailboxInvite(invite.email, invite.spaceId, accepted.toFirestore());
        } else {
          await fs.FirebaseFirestore.instance
              .collection('mailboxes')
              .doc(invite.email)
              .collection('invites')
              .doc(invite.spaceId)
              .set(accepted.toFirestore());
        }
      } catch (e) {
        debugPrint('family acceptInvite: $e');
      }
    }
    invites.value = invites.value.where((i) => i.spaceId != invite.spaceId).toList();
    await load();
  }

  Future<void> declineInvite(FamilyInvite invite) async {
    if (_synced) {
      try {
        if (_useRest) {
          await FirebaseRest.instance
              .removeMailboxInvite(invite.email, invite.spaceId);
        } else {
          await fs.FirebaseFirestore.instance
              .collection('mailboxes')
              .doc(invite.email)
              .collection('invites')
              .doc(invite.spaceId)
              .delete();
        }
      } catch (e) {
        debugPrint('family declineInvite: $e');
      }
    }
    invites.value = invites.value.where((i) => i.spaceId != invite.spaceId).toList();
    final prefs = await _p();
    await prefs.setString(
        _kInvites, jsonEncode(invites.value.map((i) => i.toMap()).toList()));
  }

  // ── Задачи-заметки ────────────────────────────────────────

  Future<List<FamilyNote>> notes(String spaceId, {bool force = false}) async {
    final prefs = await _p();
    var list = _decodeList(prefs.getString('$_kNotesPrefix$spaceId'))
        .map(FamilyNote.fromMap)
        .toList();
    if (_synced) {
      try {
        final remote = await _pull(spaceId, 'notes');
        final remoteList = remote.map(FamilyNote.fromMap).toList();
        final map = {for (final n in list) n.id: n};
        for (final r in remoteList) {
          final local = map[r.id];
          if (local == null || r.updatedAt.isAfter(local.updatedAt)) {
            map[r.id] = r;
          }
        }
        list = map.values.toList()
          ..sort((a, b) {
            if (a.done != b.done) return a.done ? 1 : -1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
        await prefs.setString('$_kNotesPrefix$spaceId',
            jsonEncode(list.map((n) => n.toMap()).toList()));
      } catch (e) {
        debugPrint('family notes pull: $e');
      }
    }
    final spaceName = _spaceNameOf(spaceId);
    for (final n in list) {
      await NotificationService.instance.checkSpaceTaskReminder(
        noteId: n.id,
        spaceId: spaceId,
        spaceName: spaceName,
        taskTitle: n.title.isEmpty ? n.content : n.title,
        taskBody: n.title.isEmpty ? '' : n.content,
        reminderDate: n.reminderDate,
        done: n.done,
      );
    }
    return list;
  }

  Future<FamilyNote> addNote({
    required String spaceId,
    required String title,
    String content = '',
    DateTime? reminderDate,
    String? assigneeUid,
  }) async {
    final note = FamilyNote.create(
      title: title,
      content: content,
      ownerUid: _uid!,
      reminderDate: reminderDate,
      assigneeUid: assigneeUid,
    );
    await _saveNote(spaceId, note);
    await _notifyTaskCreated(spaceId, note);
    return note;
  }

  /// Имя пространства для уведомлений (по кэшу списка пространств).
  String _spaceNameOf(String spaceId) {
    for (final s in spaces.value) {
      if (s.id == spaceId) return s.name;
    }
    return 'Пространство';
  }

  /// Уведомление о новой задаче в пространстве.
  /// Создателю — сразу; остальным участникам — при опросе.
  Future<void> _notifyTaskCreated(String spaceId, FamilyNote note) async {
    try {
      await NotificationService.instance.showSpaceTaskAdded(
        noteId: note.id,
        spaceId: spaceId,
        spaceName: _spaceNameOf(spaceId),
        taskTitle: note.title.isEmpty ? note.content : note.title,
        actorName: (_email ?? '').split('@').first,
      );
    } catch (e) {
      debugPrint('family taskCreated: $e');
    }
  }

  /// Задачи других участников, которых ещё не видели, → уведомление.
  Future<void> _pollSpaceTasks(
      FamilySpace space, SharedPreferences prefs) async {
    final key = 'family_knowntasks_v1_${space.id}';
    List<FamilyNote> tasks;
    try {
      tasks = await notes(space.id);
    } catch (e) {
      debugPrint('family pollSpaceTasks(${space.id}): $e');
      return;
    }
    final knownRaw = prefs.getString(key);
    if (knownRaw == null) {
      // Первый проход — запоминаем состав без уведомлений.
      await prefs.setString(
          key, jsonEncode(tasks.map((t) => t.id).toList()));
      return;
    }
    final known = <String>{
      ...(jsonDecode(knownRaw) as List<dynamic>).cast<String>(),
    };
    final fresh = tasks.where((t) => !known.contains(t.id)).toList();
    if (fresh.isEmpty) return;
    for (final t in fresh) {
      known.add(t.id);
    }
    await prefs.setString(key, jsonEncode(known.toList()));
    for (final t in fresh) {
      if (t.createdBy == _uid) continue;
      // Смотрим в этот чат на переднем плане — задачу видно в списке.
      if (appInForeground && activeChatSpaceId == space.id) continue;
      await NotificationService.instance.showSpaceTaskAdded(
        noteId: t.id,
        spaceId: space.id,
        spaceName: space.name,
        taskTitle: t.title.isEmpty ? t.content : t.title,
        actorName: familyMemberDisplayName(
            prefs.getString('$_kMembersPrefix${space.id}'), t.createdBy),
      );
    }
  }

  Future<void> updateNote(String spaceId, FamilyNote note) async {
    // Редактировать содержимое может только создатель задачи
    // (как и удалять); отметка «выполнена» доступна всем участникам
    // через toggleDone. Продублировано в firestore.rules (notes update).
    if (note.createdBy != _uid) {
      throw const RestAuthException(
        'Редактировать задачу может только её создатель',
      );
    }
    final updated = note.copyWith(updatedBy: _uid);
    await _saveNote(spaceId, updated);
  }

  Future<void> toggleDone(String spaceId, FamilyNote note) async {
    final now = DateTime.now();
    final updated = note.copyWith(
      done: !note.done,
      doneBy: !note.done ? _uid : null,
      doneAt: !note.done ? now : null,
      updatedBy: _uid,
    );
    await _saveNote(spaceId, updated);
  }

  Future<void> deleteNote(
    String spaceId,
    FamilyNote note, {
    bool? wasDone,
  }) async {
    // Удалять может только создатель задачи — правило продублировано
    // и в firestore.rules (delete: resource.data.createdBy == auth.uid).
    if (note.createdBy != _uid) {
      throw const RestAuthException(
        'Удалить задачу может только её создатель',
      );
    }
    final prefs = await _p();
    final list = await notes(spaceId)..removeWhere((n) => n.id == note.id);
    await prefs.setString('$_kNotesPrefix$spaceId',
        jsonEncode(list.map((n) => n.toMap()).toList()));
    await NotificationService.instance.cancelSpaceTask(note.id,
        forgetReminder: true);
    if (_synced) {
      try {
        await _remove(spaceId, 'notes', note.id);
        // Tombstone: чтобы остальные участники увидели, что задача удалена,
        // и локальная копия у них тоже исчезла.
        await _push(spaceId, 'deletions', note.id, {
          'noteId': note.id,
          'title': note.title,
          'deletedBy': _uid,
          'deletedByName': (_email ?? '').split('@').first,
          'deletedAt': DateTime.now().millisecondsSinceEpoch,
          'wasDone': wasDone ?? note.done,
        });
      } catch (e) {
        debugPrint('family deleteNote: $e');
      }
    }
  }

  /// Убирает локально задачи, удалённые другими участниками.
  /// Возвращает записи об удалениях (для показа «X удалил(а) задачу»).
  Future<List<Map<String, dynamic>>> reconcileDeletions(
    String spaceId,
  ) async {
    if (!_synced) return const [];
    final prefs = await _p();
    List<Map<String, dynamic>> tombs;
    try {
      tombs = await _pull(spaceId, 'deletions');
    } catch (e) {
      debugPrint('family reconcileDeletions: $e');
      return const [];
    }
    if (tombs.isEmpty) return const [];
    final list = await notes(spaceId);
    final existing = {for (final n in list) n.id: n};
    final events = <Map<String, dynamic>>[];
    var changed = false;
    for (final t in tombs) {
      final id = (t['noteId'] ?? t['id']) as String?;
      if (id == null) continue;
      if (existing.containsKey(id)) {
        list.removeWhere((n) => n.id == id);
        changed = true;
        if ((t['deletedBy'] as String?) != _uid) events.add(t);
      }
    }
    if (changed) {
      await prefs.setString('$_kNotesPrefix$spaceId',
          jsonEncode(list.map((n) => n.toMap()).toList()));
    }
    // Tombstones старше недели удаляем из облака, чтобы не копились.
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    for (final t in tombs) {
      final at = (t['deletedAt'] as num?)?.toInt() ?? 0;
      if (at < cutoff) {
        try {
          final id = (t['noteId'] ?? t['id']) as String?;
          if (id != null) await _remove(spaceId, 'deletions', id);
        } catch (_) {}
      }
    }
    return events;
  }

  Future<void> _saveNote(String spaceId, FamilyNote note) async {
    final prefs = await _p();
    final list = await notes(spaceId)
      ..removeWhere((n) => n.id == note.id)
      ..add(note);
    await prefs.setString('$_kNotesPrefix$spaceId',
        jsonEncode(list.map((n) => n.toMap()).toList()));
    if (note.done) {
      await NotificationService.instance.cancelSpaceTask(note.id);
    } else {
      await NotificationService.instance.checkSpaceTaskReminder(
        noteId: note.id,
        spaceId: spaceId,
        spaceName: _spaceNameOf(spaceId),
        taskTitle: note.title.isEmpty ? note.content : note.title,
        taskBody: note.title.isEmpty ? '' : note.content,
        reminderDate: note.reminderDate,
        done: note.done,
      );
    }
    if (_synced) {
      try {
        await _push(spaceId, 'notes', note.id, note.toFirestore());
      } catch (e) {
        debugPrint('family saveNote: $e');
      }
    }
  }

  // ── Сообщения (чат) ───────────────────────────────────────

  Future<List<FamilyMessage>> messages(String spaceId) async {
    final prefs = await _p();
    var list = _decodeList(prefs.getString('$_kMsgsPrefix$spaceId'))
        .map(FamilyMessage.fromMap)
        .toList();
    if (_synced) {
      try {
        final remote = await _pull(spaceId, 'messages');
        final remoteList = remote.map(FamilyMessage.fromMap).toList();
        final map = {for (final m in list) m.id: m};
        for (final r in remoteList) {
          map[r.id] = r;
        }
        list = map.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        // Держим в кэше последние 200 сообщений.
        if (list.length > 200) list = list.sublist(list.length - 200);
        await prefs.setString('$_kMsgsPrefix$spaceId',
            jsonEncode(list.map((m) => m.toMap()).toList()));
      } catch (e) {
        debugPrint('family messages pull: $e');
      }
    }
    return list;
  }

  Future<void> sendMessage(String spaceId, String text) async {
    final msg = FamilyMessage.create(
      text: text,
      senderUid: _uid!,
      senderEmail: _email ?? '',
      senderName: (_email ?? '').split('@').first,
    );
    final prefs = await _p();
    final list = await messages(spaceId)..add(msg);
    await prefs.setString('$_kMsgsPrefix$spaceId',
        jsonEncode(list.map((m) => m.toMap()).toList()));
    if (_synced) {
      try {
        await _push(spaceId, 'messages', msg.id, msg.toFirestore());
      } catch (e) {
        debugPrint('family sendMessage: $e');
      }
    }
  }

  // ── Утилиты ───────────────────────────────────────────────

  Future<void> _persistSpaces() async {
    final prefs = await _p();
    await prefs.setString(_kSpaces,
        jsonEncode(spaces.value.map((s) => s.toMap()).toList()));
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
