import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  Future<void> init() async {
    if (_ready || _disabled) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    try {
      await _plugin.initialize(settings: settings);

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();
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

  Future<void> scheduleForNote({
    required String noteId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready) await init();
    if (!_ready || when.isBefore(DateTime.now())) return;

    final tzWhen = tz.TZDateTime.from(when, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'planer_reminders',
      'Напоминания Планера',
      channelDescription: 'Напоминания о заметках',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id: _notifId(noteId),
      title: title.isEmpty ? 'Напоминание' : title,
      body: body.isEmpty ? 'Пора посмотреть заметку' : body,
      scheduledDate: tzWhen,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
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
      );
    }
  }

  /// Показывает уведомление сразу (например, о новом сообщении в чате).
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
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
    await _plugin.show(id: id, title: title, body: body, notificationDetails: details);
  }

  Future<void> cancelForNote(String noteId) async {
    if (!_ready) await init();
    if (!_ready) return;
    await _plugin.cancel(id: _notifId(noteId));
  }

  Future<void> cancelAll() async {
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
