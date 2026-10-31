import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'cloud_service.dart';
import 'models/standalone_reminder.dart';
import 'notifications.dart';

/// Напоминания без привязки к заметкам: разделы + ежегодный повтор.
/// Local-first, с репликацией в Firestore (как и заметки).
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final ValueNotifier<List<StandaloneReminder>> reminders =
      ValueNotifier<List<StandaloneReminder>>([]);
  final ValueNotifier<List<ReminderSection>> sections =
      ValueNotifier<List<ReminderSection>>([]);

  static const _kRemindersPrefix = 'standalone_reminders_v2_';
  static const _kSectionsPrefix = 'reminder_sections_v1_';

  Future<SharedPreferences> _p() => SharedPreferences.getInstance();

  String _remKey(String ownerKey) => '$_kRemindersPrefix$ownerKey';
  String _secKey(String ownerKey) => '$_kSectionsPrefix$ownerKey';

  List<StandaloneReminder> get all => reminders.value;
  List<ReminderSection> get allSections => sections.value;

  bool get _synced =>
      !AuthService.instance.isGuest.value &&
      AuthService.instance.ownerKey != 'guest';

  Future<void> load() async {
    final key = AuthService.instance.ownerKey;
    final prefs = await _p();
    await _migrateLegacy(prefs, key);
    var rem = _decodeReminders(prefs.getString(_remKey(key)));
    var secs = _decodeSections(prefs.getString(_secKey(key)));

    if (_synced) {
      final remoteRemIds = <String>{};
      final remote = await CloudNotesService.instance.pullReminders(key);
      if (remote != null) {
        final map = {for (final r in rem) r.id: r};
        for (final r in remote) {
          remoteRemIds.add(r.id);
          final local = map[r.id];
          if (local == null || r.fireAt.isAfter(local.fireAt) || local.done != r.done) {
            map[r.id] = r;
          }
        }
        rem = map.values.toList();
      }

      final remoteSecIds = <String>{};
      final remoteSecs = await CloudNotesService.instance.pullReminderSections(key);
      if (remoteSecs != null) {
        final map = {for (final s in secs) s.id: s};
        for (final r in remoteSecs) {
          remoteSecIds.add(r.id);
          final local = map[r.id];
          if (local == null || r.updatedAt.isAfter(local.updatedAt)) {
            map[r.id] = r;
          }
        }
        secs = map.values.toList();
      }

      // Догружаем в облако то, чего там ещё нет (чинит потерянные разделы).
      final missingRem = rem.where((r) => !remoteRemIds.contains(r.id)).toList();
      final missingSec = secs.where((s) => !remoteSecIds.contains(s.id)).toList();
      if (missingRem.isNotEmpty) {
        await CloudNotesService.instance.pushAllReminders(key, missingRem);
      }
      if (missingSec.isNotEmpty) {
        await CloudNotesService.instance.pushAllReminderSections(key, missingSec);
      }
    }

    reminders.value = rem;
    sections.value = secs;
    await _rolloverYearly();
    await _persistAll();
    await _rescheduleAll();
  }

  // ── Разделы ───────────────────────────────────────────────

  Future<ReminderSection> createSection({
    required String title,
    int colorIndex = 0,
  }) async {
    final key = AuthService.instance.ownerKey;
    final section = ReminderSection.create(
      title: title,
      ownerKey: key,
      colorIndex: colorIndex,
    );
    sections.value = [...sections.value, section];
    await _persistAll();
    if (_synced) {
      await CloudNotesService.instance.upsertReminderSection(key, section);
    }
    return section;
  }

  Future<void> updateSection(ReminderSection section) async {
    final key = AuthService.instance.ownerKey;
    final updated = section.copyWith(
      title: section.title,
      colorIndex: section.colorIndex,
    );
    sections.value =
        sections.value.map((s) => s.id == updated.id ? updated : s).toList();
    await _persistAll();
    if (_synced) {
      await CloudNotesService.instance.upsertReminderSection(key, updated);
    }
  }

  Future<void> deleteSection(ReminderSection section) async {
    final key = AuthService.instance.ownerKey;
    final movedIds = <String>{
      for (final r in reminders.value)
        if (r.sectionId == section.id) r.id,
    };
    reminders.value = reminders.value.map((r) {
      if (r.sectionId == section.id) {
        return r.copyWith(sectionId: null, clearSection: true);
      }
      return r;
    }).toList();
    sections.value =
        sections.value.where((s) => s.id != section.id).toList();
    await _persistAll();
    if (_synced) {
      await CloudNotesService.instance.deleteReminderSection(key, section.id);
      for (final r in reminders.value.where((r) => movedIds.contains(r.id))) {
        await CloudNotesService.instance.upsertReminder(key, r);
      }
    }
  }

  ReminderSection? sectionById(String? id) {
    if (id == null) return null;
    for (final s in sections.value) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Напоминания раздела. Без раздела — включая «сирот» (раздел не
  /// восстановился), иначе они пропадают из интерфейса.
  List<StandaloneReminder> remindersIn(String? sectionId) {
    if (sectionId == null) {
      return reminders.value
          .where((r) => r.sectionId == null || sectionById(r.sectionId) == null)
          .toList()
        ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    }
    return reminders.value.where((r) => r.sectionId == sectionId).toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }

  int countIn(String? sectionId) => remindersIn(sectionId).length;

  // ── Напоминания ───────────────────────────────────────────

  Future<void> add(StandaloneReminder reminder) async {
    final key = AuthService.instance.ownerKey;
    final owned = reminder.copyWith(ownerKey: key);
    reminders.value = [...reminders.value, owned];
    await _persistAll();
    await _schedule(owned);
    if (_synced) {
      await CloudNotesService.instance.upsertReminder(key, owned);
    }
  }

  Future<void> update(StandaloneReminder reminder) async {
    final key = AuthService.instance.ownerKey;
    final owned = reminder.copyWith(ownerKey: key);
    reminders.value = reminders.value
        .map((r) => r.id == owned.id ? owned : r)
        .toList();
    await _persistAll();
    await _schedule(owned);
    if (_synced) {
      await CloudNotesService.instance.upsertReminder(key, owned);
    }
  }

  Future<void> remove(StandaloneReminder reminder) async {
    final key = AuthService.instance.ownerKey;
    reminders.value =
        reminders.value.where((r) => r.id != reminder.id).toList();
    await _persistAll();
    try {
      await NotificationService.instance.cancelForNote(reminder.id);
    } catch (_) {}
    if (_synced) {
      await CloudNotesService.instance.deleteReminder(key, reminder.id);
    }
  }

  Future<void> toggleDone(StandaloneReminder reminder) async {
    await update(reminder.copyWith(done: !reminder.done));
  }

  /// Перенос напоминания в раздел (null — без раздела).
  Future<void> moveToSection(StandaloneReminder r, String? sectionId) async {
    await update(r.copyWith(sectionId: sectionId, clearSection: sectionId == null));
  }

  /// Ежегодные напоминания, чья дата прошла, переносятся на следующий год.
  Future<void> _rolloverYearly() async {
    final now = DateTime.now();
    var changed = false;
    final list = reminders.value.map((r) {
      if (!r.yearly || r.fireAt.isAfter(now)) return r;
      changed = true;
      return r.copyWith(fireAt: r.nextYear(), done: false);
    }).toList();
    if (!changed) return;
    reminders.value = list;
    for (final r in list) {
      await _schedule(r);
    }
    if (_synced) {
      await CloudNotesService.instance.pushAllReminders(
        AuthService.instance.ownerKey,
        list.where((r) => r.yearly).toList(),
      );
    }
  }

  // ── Выборки ───────────────────────────────────────────────

  List<StandaloneReminder> upcoming() {
    final now = DateTime.now();
    final list = reminders.value
        .where((r) => !r.done && r.fireAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return list;
  }

  List<StandaloneReminder> past() {
    final now = DateTime.now();
    final list = reminders.value
        .where((r) => r.done || r.fireAt.isBefore(now))
        .toList()
      ..sort((a, b) => b.fireAt.compareTo(a.fireAt));
    return list;
  }

  List<StandaloneReminder> onDay(DateTime day) {
    return reminders.value.where((r) {
      return r.fireAt.year == day.year &&
          r.fireAt.month == day.month &&
          r.fireAt.day == day.day;
    }).toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }

  // ── Внутреннее ────────────────────────────────────────────

  /// Старые версии держали все напоминания в одном ключе без разделов.
  static const _kLegacy = 'standalone_reminders_v1';

  Future<void> _migrateLegacy(SharedPreferences prefs, String key) async {
    final raw = prefs.getString(_kLegacy);
    if (raw == null || raw.isEmpty) return;
    final legacy = _decodeReminders(raw);
    if (legacy.isNotEmpty) {
      final existing = _decodeReminders(prefs.getString(_remKey(key)));
      final ids = existing.map((e) => e.id).toSet();
      final merged = [...existing];
      for (final r in legacy) {
        if (ids.add(r.id)) {
          merged.add(r.copyWith(ownerKey: key));
        }
      }
      await prefs.setString(
        _remKey(key),
        jsonEncode(merged.map((e) => e.toJson()).toList()),
      );
    }
    await prefs.remove(_kLegacy);
  }

  List<StandaloneReminder> _decodeReminders(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              StandaloneReminder.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<ReminderSection> _decodeSections(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              ReminderSection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistAll() async {
    final key = AuthService.instance.ownerKey;
    final prefs = await _p();
    await prefs.setString(
      _remKey(key),
      jsonEncode(reminders.value.map((r) => r.toJson()).toList()),
    );
    await prefs.setString(
      _secKey(key),
      jsonEncode(sections.value.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _rescheduleAll() async {
    for (final r in reminders.value) {
      await _schedule(r);
    }
  }

  Future<void> _schedule(StandaloneReminder r) async {
    try {
      if (r.done || r.fireAt.isBefore(DateTime.now())) {
        await NotificationService.instance.cancelForNote(r.id);
        return;
      }
      await NotificationService.instance.scheduleForNote(
        noteId: r.id,
        title: r.title,
        body: r.body ?? 'Напоминание из Планера',
        when: r.fireAt,
      );
    } catch (e) {
      debugPrint('standalone reminder schedule: $e');
    }
  }
}
