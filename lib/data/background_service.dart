import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'models/family_space.dart';
import 'models/standalone_reminder.dart';
import 'notifications.dart';

const _taskName = 'planer.background.sync';

/// Прежние будильники android_alarm_manager_plus — снимаются при старте.
/// Их JobIntentService отпускал job до старта Dart-движка, HiOS замораживал
/// процесс, и колбэк не выполнялся до открытия приложения.
const _alarmChainId = 870151;
const _alarmRepeatId = 870152;

/// Точка входа фоновой задачи WorkManager (запасной механизм).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await runBackgroundCheck();
    return true;
  });
}

/// Точка входа нативного фон-сервиса BgCheckService (см.
/// android/app/src/main/kotlin/ru/planer/notes/BgCheckService.kt).
/// Foreground-сервис держит процесс размороженным, пока идёт проверка.
@pragma('vm:entry-point')
void bgServiceMain() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('planer.bg/finish');
  void finish() {
    try {
      channel.invokeMethod('done');
    } catch (_) {}
  }

  Future<void>.delayed(const Duration(seconds: 50), finish);
  runBackgroundCheck().whenComplete(finish);
}

/// Общая фоновая проверка: повторы напоминаний + новые сообщения/задачи
/// в общих пространствах. Запускается будильником и WorkManager-воркером.
Future<void> runBackgroundCheck() async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {
    // Изолят движка и так имеет плагины — не критично.
  }
  debugPrint('bg check start ${DateTime.now().toIso8601String()}');
  try {
    await NotificationService.instance.init();
    await _rollRepeatingReminders();
    await _notifySpaceUpdates();
    debugPrint('bg check done');
  } catch (e) {
    debugPrint('bg check error: $e');
  }
  await _maybeTestNotice();
}

/// Одноразовое уведомление-подтверждение: фоновая проверка реально работает.
Future<void> _maybeTestNotice() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('bg_alarm_ping_v1') ?? false) return;
    await prefs.setBool('bg_alarm_ping_v1', true);
    await NotificationService.instance.showNow(
      id: 999001,
      title: 'Фоновые уведомления включены',
      body: 'Планер проверяет новые сообщения и задачи в «Общих»',
    );
  } catch (e) {
    debugPrint('bg test notice: $e');
  }
}

/// Регистрирует фоновые механизмы (только Android).
class BackgroundService {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  Future<void> init() async {
    if (!Platform.isAndroid) return;

    // Основной механизм — нативная цепочка BgCheckReceiver/BgCheckService
    // (ставится в MainActivity.onCreate и самовосстанавливается в приёмнике).
    // Здесь только гасим будильники прежнего механизма плагина.
    try {
      await AndroidAlarmManager.initialize();
      await AndroidAlarmManager.cancel(_alarmChainId);
      await AndroidAlarmManager.cancel(_alarmRepeatId);
      debugPrint('bg old alarms cancelled');
    } catch (e) {
      debugPrint('bg alarm cleanup: $e');
    }

    // Запасной механизм: WorkManager переживает перезагрузку даже без будильников.
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 2),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      debugPrint('background task registered');
    } catch (e) {
      debugPrint('background init: $e');
    }
  }
}

/// Повторяющиеся напоминания, чья дата прошла, переносятся на следующее
/// срабатывание и планируются — иначе цепочка повторов обрывается, пока
/// приложение не открыли.
Future<void> _rollRepeatingReminders() async {
  final prefs = await SharedPreferences.getInstance();
  final key = prefs.getString('owner_key') ?? 'guest';
  final raw = prefs.getString('standalone_reminders_v2_$key');
  if (raw == null || raw.isEmpty) return;

  List<StandaloneReminder> list;
  try {
    list = (jsonDecode(raw) as List<dynamic>)
        .map((e) =>
            StandaloneReminder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return;
  }

  final now = DateTime.now();
  var changed = false;
  for (var i = 0; i < list.length; i++) {
    final r = list[i];
    if (r.done) continue;
    if (r.hasRepeat && !r.fireAt.isAfter(now)) {
      final next = r.nextOccurrence(now);
      if (next == null) continue;
      final rolled = r.copyWith(fireAt: next, done: false);
      list[i] = rolled;
      changed = true;
      await NotificationService.instance.scheduleForNote(
        noteId: rolled.id,
        title: rolled.title.isEmpty
            ? 'Напоминание'
            : 'Напоминание: ${rolled.title}',
        body: rolled.body ?? 'Пора посмотреть',
        when: rolled.fireAt,
        payload: 'rem:${rolled.id}',
      );
    } else if (r.fireAt.isAfter(now)) {
      // Переподтверждаем расписание одиночных — страховка после
      // force-stop/перезагрузки, когда своё напоминание могло потеряться.
      await NotificationService.instance.scheduleForNote(
        noteId: r.id,
        title: r.title.isEmpty
            ? 'Напоминание'
            : 'Напоминание: ${r.title}',
        body: r.body ?? 'Пора посмотреть',
        when: r.fireAt,
        payload: 'rem:${r.id}',
      );
    }
  }
  if (!changed) return;
  await prefs.setString(
    'standalone_reminders_v2_$key',
    jsonEncode(list.map((e) => e.toJson()).toList()),
  );
}

/// Новые чужие сообщения и задачи в общих пространствах → локальное уведомление.
/// Ключи SharedPreferences совпадают с FamilyService (см. family_service.dart).
Future<void> _notifySpaceUpdates() async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  final uid = prefs.getString('owner_key');
  if (uid == null || uid == 'guest') return;

  final spacesRaw = prefs.getString('family_spaces_cache_v1');
  if (spacesRaw == null || spacesRaw.isEmpty) return;

  // Чат, открытый на экране, не шумит, только пока приложение на переднем
  // плане (см. FamilyService.activeChatSpaceId / prefs app_foreground_v1).
  final activeChat = prefs.getString('active_chat_space_v1');
  final fg = prefs.getBool('app_foreground_v1') ?? false;

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Уже инициализировано или нет google-services — пробуем дальше.
  }
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
    }
  } catch (e) {
    debugPrint('bg auth wait: $e');
    return; // нет сохранённого входа — проверить нечего
  }

  final spaces = (jsonDecode(spacesRaw) as List<dynamic>)
      .map((e) => FamilySpace.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();

  for (final space in spaces) {
    try {
      await _checkNewSpaceTasks(prefs, uid, space);

      final snap = await FirebaseFirestore.instance
          .collection('family_spaces')
          .doc(space.id)
          .collection('messages')
          .limit(30)
          .get();

      final msgs = snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return FamilyMessage.fromMap(data);
      }).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (msgs.isEmpty) continue;

      final lastKey = 'family_lastmsg_v1_${space.id}';
      final lastSeenId = prefs.getString(lastKey);
      final lastMsg = msgs.last;
      if (lastSeenId == lastMsg.id) continue;

      var newCount = 0;
      for (final m in msgs.reversed) {
        if (m.id == lastSeenId) break;
        if (m.senderUid != uid) newCount++;
      }
      await prefs.setString(lastKey, lastMsg.id);
      if (newCount == 0) continue;
      // Смотрим в этот чат на переднем плане — сообщение видно в списке.
      // Свёрнутое приложение обязано уведомлять (и считать непрочитанные).
      if (fg && activeChat == space.id) continue;

      final lastForeign = msgs.lastWhere(
        (m) => m.senderUid != uid,
        orElse: () => lastMsg,
      );
      await NotificationService.instance.showSpaceChatMessage(
        spaceId: space.id,
        spaceName: space.name,
        senderName: lastForeign.senderName,
        text: lastForeign.text,
      );
      final unread =
          (int.tryParse(prefs.getString('family_unread_v1_${space.id}') ?? '') ??
                  0) +
              newCount;
      await prefs.setString('family_unread_v1_${space.id}', '$unread');
    } catch (e) {
      debugPrint('background chat ${space.id}: $e');
    }
  }
}

/// Новые задачи от других участников → уведомление «Новая задача…»;
/// напоминания задач — простые одноразовые уведомления (не будильник).
Future<void> _checkNewSpaceTasks(
    SharedPreferences prefs, String uid, FamilySpace space) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('family_spaces')
        .doc(space.id)
        .collection('notes')
        .limit(50)
        .get();
    final tasks = snap.docs.map((d) {
      final data = d.data();
      data['id'] = data['id'] ?? d.id;
      return FamilyNote.fromMap(data);
    }).toList();

    for (final t in tasks) {
      await NotificationService.instance.checkSpaceTaskReminder(
        noteId: t.id,
        spaceId: space.id,
        spaceName: space.name,
        taskTitle: t.title.isEmpty ? t.content : t.title,
        taskBody: t.title.isEmpty ? '' : t.content,
        reminderDate: t.reminderDate,
        done: t.done,
      );
    }

    final key = 'family_knowntasks_v1_${space.id}';
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
    // Уведомляем всегда, кроме случая «приложение на переднем плане
    // с открытым экраном этого пространства» — задачу там видно в списке.
    final fg = prefs.getBool('app_foreground_v1') ?? false;
    final activeChat = prefs.getString('active_chat_space_v1');
    for (final t in fresh) {
      if (t.createdBy == uid) continue;
      if (fg && activeChat == space.id) continue;
      await NotificationService.instance.showSpaceTaskAdded(
        noteId: t.id,
        spaceId: space.id,
        spaceName: space.name,
        taskTitle: t.title.isEmpty ? t.content : t.title,
        actorName: familyMemberDisplayName(
            prefs.getString('family_members_v1_${space.id}'), t.createdBy),
      );
    }
  } catch (e) {
    debugPrint('background tasks ${space.id}: $e');
  }
}
