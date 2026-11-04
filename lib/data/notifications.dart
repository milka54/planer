import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _disabled = false;
  bool get isReady => _ready;

  /// Обработчик тапа по уведомлению (регистрирует HomeShell).
  /// Формат payload: 'note:<id>' | 'rem:<id>' | 'chat:<spaceId>' | 'task:<spaceId>'.
  static void Function(String payload)? onTap;

  /// Payload уведомления, из-за которого приложение было запущено.
  static String? _launchPayload;

  /// Забирает (и очищает) payload холодного старта из уведомления.
  static String? consumeLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  static void _onTap(NotificationResponse res) {
    final p = res.payload;
    if (p == null || p.isEmpty) return;
    final handler = onTap;
    if (handler != null) {
      handler(p);
    } else {
      _launchPayload = p;
    }
  }

  Future<void> init() async {
    if (_ready || _disabled) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const windows = WindowsInitializationSettings(
      appName: 'Планер',
      appUserModelId: 'ru.planer.notes',
      guid: '5f2b7a1e-9c4d-4b6a-8e2f-1a3b5c7d9e0f',
    );
    const settings =
        InitializationSettings(android: android, iOS: ios, windows: windows);

    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onTap,
      );

      // Холодный старт по тапу на уведомление — сохраняем payload,
      // пока HomeShell не зарегистрирует обработчик.
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) {
          _launchPayload = launch?.notificationResponse?.payload;
        }
      } catch (_) {}

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        // Разрешения — по одному: сбой одного не выключает все уведомления.
        try {
          await androidImpl.requestNotificationsPermission();
        } catch (e) {
          debugPrint('notif permission: $e');
        }
        try {
          await androidImpl.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint('exact alarm permission: $e');
        }
      }
      _ready = true;
    } catch (e) {
      // Платформы без локальных уведомлений (Windows/desktop) —
      // работаем без них, приложение от этого не должно падать.
      _disabled = true;
      debugPrint('notifications disabled: $e');
    }
  }

  static int _notifId(String noteId) => noteId.hashCode & 0x7fffffff;

  /// Плановое уведомление через таймер (Windows/desktop: zonedSchedule
  /// не поддерживается, но приложение живёт в трее — таймер сработает).
  static final Map<String, Timer> _timers = {};

  Future<void> scheduleForNote({
    required String noteId,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;

    // Просроченное в пределах короткого окна («сейчас») — показываем
    // сразу: zonedSchedule требует будущую дату, а молча терять
    // напоминание нельзя. Старое просроченное не шумим.
    final now = DateTime.now();
    if (when.isBefore(now)) {
      if (when.isAfter(now.subtract(const Duration(minutes: 5)))) {
        await showNow(
          id: _notifId(noteId),
          title: title.isEmpty ? 'Напоминание' : title,
          body: body.isEmpty ? 'Пора посмотреть заметку' : body,
          payload: payload,
        );
      }
      return;
    }

    final title_ = title.isEmpty ? 'Напоминание' : title;
    final body_ = body.isEmpty ? 'Пора посмотреть заметку' : body;

    // Резервный таймер — срабатывает, пока процесс жив
    // (приложение свёрнуто). Основной механизм — zonedSchedule
    // (AlarmManager): переживает убийство процесса. Одинаковый
    // id — повторный show() заменяет уведомление, не дублируя.
    _timers[noteId]?.cancel();
    _timers[noteId] = Timer(when.difference(DateTime.now()), () {
      showNow(id: _notifId(noteId), title: title_, body: body_, payload: payload);
    });

    if (!Platform.isAndroid && !Platform.isIOS) {
      return; // desktop: zonedSchedule не поддержан — достаточно таймера
    }

    final tzWhen = tz.TZDateTime.from(when, tz.local);

    final androidDetails = AndroidNotificationDetails(
      'planer_reminders',
      'Напоминания Планера',
      channelDescription: 'Напоминания о заметках',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body_),
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Без права точных будильников exactAllowWhileIdle падает —
    // пробуем неточный режим, чтобы уведомление всё равно пришло.
    for (final mode in const [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]) {
      try {
        await _plugin.zonedSchedule(
          id: _notifId(noteId),
          title: title_,
          body: body_,
          scheduledDate: tzWhen,
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: payload,
        );
        return;
      } catch (e) {
        debugPrint('zonedSchedule($mode): $e');
      }
    }
  }

  /// Перепланирует уведомления для всех заметок с напоминаниями.
  /// Нужно после синхронизации: заметки приходят с reminderDate,
  /// но локальные уведомления на новом устройстве ещё не созданы.
  Future<void> rescheduleAllForNotes(Iterable<dynamic> notes) async {
    if (!_ready) await init();
    if (!_ready) return;
    for (final n in notes) {
      final when = n.reminderDate as DateTime?;
      if (when == null) continue;
      await scheduleForNote(
        noteId: n.id as String,
        title: (n.title as String?) ?? '',
        body: (n.preview as String?) ?? '',
        when: when,
        payload: 'note:${n.id}',
      );
    }
  }

  /// Показывает уведомление сразу (например, о новом сообщении в чате).
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    const androidDetails = AndroidNotificationDetails(
      'planer_messages',
      'Сообщения Планера',
      channelDescription: 'Новые сообщения в общих заметках',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  static int _spaceAddId(String noteId) =>
      ('add:$noteId').hashCode & 0x7fffffff;
  static int _spaceRemId(String noteId) =>
      ('rem:$noteId').hashCode & 0x7fffffff;

  static const _remFiredPrefix = 'space_rem_fired_v1_';

  /// «Новая задача в пространстве» — простое одноразовое уведомление.
  Future<void> showSpaceTaskAdded({
    required String noteId,
    required String spaceId,
    required String spaceName,
    required String taskTitle,
    String? actorName,
  }) async {
    final body = (actorName == null || actorName.isEmpty)
        ? taskTitle
        : '$actorName: $taskTitle';
    await showNow(
      id: _spaceAddId(noteId),
      title: 'Новая задача в пространстве «$spaceName»',
      body: body,
      payload: 'task:$spaceId',
    );
  }

  /// «Сообщение в пространстве» — простое уведомление о новом сообщении чата.
  /// Новое сообщение заменяет предыдущее (один id на пространство).
  Future<void> showSpaceChatMessage({
    required String spaceId,
    required String spaceName,
    required String senderName,
    required String text,
  }) async {
    await showNow(
      id: spaceId.hashCode & 0x7fffffff,
      title: 'Сообщение в пространстве «$spaceName»',
      body: senderName.isEmpty ? text : '$senderName: $text',
      payload: 'chat:$spaceId',
    );
  }

  /// «Напоминание по задаче» — простое уведомление в момент напоминания.
  /// Без планирования-будильника и без повторов.
  Future<void> showSpaceTaskReminder({
    required String noteId,
    required String spaceId,
    required String spaceName,
    required String taskTitle,
    String? taskBody,
  }) async {
    final body =
        (taskBody == null || taskBody.isEmpty) ? 'Пора выполнить' : taskBody;
    await showNow(
      id: _spaceRemId(noteId),
      title: 'Напоминание по задаче в пространстве «$spaceName»',
      body: taskTitle.isEmpty ? body : '$taskTitle — $body',
      payload: 'task:$spaceId',
    );
  }

  /// Одноразовое срабатывание напоминания задачи общего пространства:
  /// показывает ровно один раз на каждую дату reminderDate (без спама).
  Future<void> checkSpaceTaskReminder({
    required String noteId,
    required String spaceId,
    required String spaceName,
    required String taskTitle,
    String? taskBody,
    required DateTime? reminderDate,
    required bool done,
  }) async {
    if (done || reminderDate == null) return;
    final now = DateTime.now();
    if (reminderDate.isAfter(now)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_remFiredPrefix$noteId';
    final marker = reminderDate.millisecondsSinceEpoch.toString();
    if (prefs.getString(key) == marker) return;
    if (now.difference(reminderDate) > const Duration(hours: 24)) {
      // Старое просроченное не шумим — это не будильник.
      await prefs.setString(key, marker);
      return;
    }
    await showSpaceTaskReminder(
      noteId: noteId,
      spaceId: spaceId,
      spaceName: spaceName,
      taskTitle: taskTitle,
      taskBody: taskBody,
    );
    await prefs.setString(key, marker);
  }

  /// Гасит уведомления задачи пространства; forgetReminder — снять и отметку
  /// «напоминание показано» (задача удалена).
  Future<void> cancelSpaceTask(String noteId,
      {bool forgetReminder = false}) async {
    if (forgetReminder) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_remFiredPrefix$noteId');
    }
    if (!_ready) await init();
    if (!_ready) return;
    await _plugin.cancel(id: _spaceAddId(noteId));
    await _plugin.cancel(id: _spaceRemId(noteId));
  }

  Future<void> cancelForNote(String noteId) async {
    _timers.remove(noteId)?.cancel();
    if (!_ready) await init();
    if (!_ready) return;
    await _plugin.cancel(id: _notifId(noteId));
  }

  Future<void> cancelAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    if (!_ready) await init();
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  Future<List<PendingNotificationRequest>> pending() async {
    if (!_ready) await init();
    if (!_ready) return const [];
    return _plugin.pendingNotificationRequests();
  }

  void debugLog(String msg) {
    if (kDebugMode) debugPrint('[notif] $msg');
  }
}
