import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'cloud_service.dart';
import 'models/note.dart';
import 'notifications.dart';
import 'storage.dart';

/// Local-first репозиторий: разделы + заметки.
class NotesRepository {
  NotesRepository._();
  static final NotesRepository instance = NotesRepository._();

  final ValueNotifier<List<Note>> notes = ValueNotifier<List<Note>>([]);
  final ValueNotifier<List<NoteSection>> sections =
      ValueNotifier<List<NoteSection>>([]);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  List<Note> get all => notes.value;
  List<NoteSection> get allSections => sections.value;

  List<Note> get activeSorted {
    final list = notes.value.where((n) => !n.archived).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return list;
  }

  List<Note> get archivedSorted {
    final list = notes.value.where((n) => n.archived).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<Note> get remindersSorted {
    final list = notes.value.where((n) => n.hasReminder && !n.archived).toList()
      ..sort((a, b) => a.reminderDate!.compareTo(b.reminderDate!));
    return list;
  }

  /// Заметки раздела. Без раздела (sectionId == null) показываем и «сирот» —
  /// тех, чей раздел не восстановился из облака. Иначе они пропадают из UI.
  List<Note> notesIn(String? sectionId) {
    if (sectionId == null) {
      return activeSorted
          .where((n) => n.sectionId == null || sectionById(n.sectionId) == null)
          .toList();
    }
    return activeSorted.where((n) => n.sectionId == sectionId).toList();
  }

  int noteCount(String? sectionId) => notesIn(sectionId).length;

  NoteSection? sectionById(String? id) {
    if (id == null) return null;
    for (final s in sections.value) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    loading.value = true;
    final key = AuthService.instance.ownerKey;
    var list = await StorageService.instance.loadNotes(key);
    var secs = await StorageService.instance.loadSections(key);

    final signedIn = !AuthService.instance.isGuest.value && key != 'guest';
    if (signedIn) {
      final remoteIds = <String>{};
      final remote = await CloudNotesService.instance.pullAll(key);
      if (remote != null) {
        final map = {for (final n in list) n.id: n};
        for (final r in remote) {
          remoteIds.add(r.id);
          final local = map[r.id];
          if (local == null || r.updatedAt.isAfter(local.updatedAt)) {
            map[r.id] = r;
          }
        }
        list = map.values.toList();
        await StorageService.instance.saveNotes(key, list);
      }

      final remoteSecIds = <String>{};
      final remoteSecs = await CloudNotesService.instance.pullSections(key);
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
        await StorageService.instance.saveSections(key, secs);
      }

      // Догружаем в облако то, чего там ещё нет. Это чинит разделы,
      // потерявшиеся из-за молчаливого сбоя записи: устройство, где раздел
      // ещё есть локально, выгрузит его, и второе устройство его подтянет.
      final missingNotes =
          list.where((n) => !remoteIds.contains(n.id)).toList();
      final missingSecs =
          secs.where((s) => !remoteSecIds.contains(s.id)).toList();
      if (missingNotes.isNotEmpty) {
        await CloudNotesService.instance.pushAll(key, missingNotes);
      }
      if (missingSecs.isNotEmpty) {
        await CloudNotesService.instance.pushAllSections(key, missingSecs);
      }
    }

    notes.value = list;
    sections.value = secs;
    loading.value = false;

    // После синхронизации перепланируем уведомления: на новом устройстве
    // заметки с reminderDate приходят из облака, но локальных уведомлений нет.
    try {
      await NotificationService.instance.rescheduleAllForNotes(
        list.where((n) => n.hasReminder),
      );
    } catch (e) {
      debugPrint('reschedule after load: $e');
    }
  }

  // ── Разделы ───────────────────────────────────────────────

  Future<NoteSection> createSection({
    required String title,
    int colorIndex = 0,
  }) async {
    final key = AuthService.instance.ownerKey;
    final section = NoteSection.create(
      title: title,
      ownerKey: key,
      colorIndex: colorIndex,
    );
    final list = [...sections.value, section];
    await _persistSections(list, key);
    if (!AuthService.instance.isGuest.value && key != 'guest') {
      await CloudNotesService.instance.upsertSection(key, section);
    }
    return section;
  }

  Future<void> updateSection(NoteSection section) async {
    final key = AuthService.instance.ownerKey;
    final updated = section.copyWith(
      title: section.title,
      colorIndex: section.colorIndex,
    );
    final list =
        sections.value.map((s) => s.id == updated.id ? updated : s).toList();
    await _persistSections(list, key);
    if (!AuthService.instance.isGuest.value && key != 'guest') {
      await CloudNotesService.instance.upsertSection(key, updated);
    }
  }

  /// Удаляет раздел вместе со всеми его заметками (включая уведомления).
  Future<void> deleteSection(NoteSection section) async {
    final key = AuthService.instance.ownerKey;
    final doomed =
        notes.value.where((n) => n.sectionId == section.id).toList();

    // Отменяем уведомления удаляемых заметок.
    for (final n in doomed) {
      if (n.hasReminder) {
        try {
          await NotificationService.instance.cancelForNote(n.id);
        } catch (_) {}
      }
    }

    final remaining = notes.value
        .where((n) => n.sectionId != section.id)
        .toList();
    await _persist(remaining, key);

    final list = sections.value.where((s) => s.id != section.id).toList();
    await _persistSections(list, key);

    if (!AuthService.instance.isGuest.value && key != 'guest') {
      for (final n in doomed) {
        try {
          await CloudNotesService.instance.delete(key, n.id);
        } catch (_) {}
      }
      await CloudNotesService.instance.deleteSection(key, section.id);
    }
  }

  // ── Заметки ───────────────────────────────────────────────

  Future<Note> create({
    required String title,
    required String content,
    String? sectionId,
    DateTime? reminderDate,
    int colorIndex = 0,
    List<String>? voicePaths,
  }) async {
    final key = AuthService.instance.ownerKey;
    final note = Note.create(
      title: title,
      content: content,
      ownerKey: key,
      sectionId: sectionId,
      reminderDate: reminderDate,
      colorIndex: colorIndex,
      voicePaths: voicePaths,
    );
    final list = [...notes.value, note];
    await _persist(list, key);
    await _syncReminder(note);
    if (!AuthService.instance.isGuest.value && key != 'guest') {
      CloudNotesService.instance.upsert(key, note);
    }
    return note;
  }

  Future<void> update(Note note, {bool clearReminder = false}) async {
    final key = AuthService.instance.ownerKey;
    final updated = note.copyWith(
      title: note.title,
      content: note.content,
      reminderDate: note.reminderDate,
      clearReminder: clearReminder,
      colorIndex: note.colorIndex,
      pinned: note.pinned,
      archived: note.archived,
      sectionId: note.sectionId,
      voicePaths: note.voicePaths,
    );
    final list = notes.value.map((n) => n.id == updated.id ? updated : n).toList();
    await _persist(list, key);
    await _syncReminder(updated);
    if (!AuthService.instance.isGuest.value && key != 'guest') {
      CloudNotesService.instance.upsert(key, updated);
    }
  }

  Future<void> replaceInMemory(Note updated) async {
    final key = AuthService.instance.ownerKey;
    final list =
        notes.value.map((n) => n.id == updated.id ? updated : n).toList();
    await _persist(list, key);
  }

  Future<void> delete(Note note) async {
    final key = AuthService.instance.ownerKey;
    if (note.hasReminder) {
      await NotificationService.instance.cancelForNote(note.id);
    }
    final list = notes.value.where((n) => n.id != note.id).toList();
    await _persist(list, key);
    if (!AuthService.instance.isGuest.value && key != 'guest') {
      CloudNotesService.instance.delete(key, note.id);
    }
  }

  Future<void> togglePin(Note note) async {
    final updated = note.copyWith(pinned: !note.pinned);
    await replaceInMemory(updated);
    if (!AuthService.instance.isGuest.value &&
        AuthService.instance.ownerKey != 'guest') {
      CloudNotesService.instance.upsert(AuthService.instance.ownerKey, updated);
    }
  }

  Future<void> toggleArchive(Note note) async {
    final updated = note.copyWith(archived: !note.archived);
    await replaceInMemory(updated);
    if (!AuthService.instance.isGuest.value &&
        AuthService.instance.ownerKey != 'guest') {
      CloudNotesService.instance.upsert(AuthService.instance.ownerKey, updated);
    }
  }

  Future<void> setReminder(Note note, DateTime? when) async {
    final updated = note.copyWith(
      reminderDate: when,
      clearReminder: when == null,
    );
    await replaceInMemory(updated);
    await _syncReminder(updated);
    if (!AuthService.instance.isGuest.value &&
        AuthService.instance.ownerKey != 'guest') {
      CloudNotesService.instance.upsert(AuthService.instance.ownerKey, updated);
    }
  }

  /// Перенос заметки в раздел (null — на главный экран).
  Future<void> moveToSection(Note note, String? sectionId) async {
    final updated = note.copyWith(
      sectionId: sectionId,
      clearSection: sectionId == null,
    );
    await replaceInMemory(updated);
    if (!AuthService.instance.isGuest.value &&
        AuthService.instance.ownerKey != 'guest') {
      CloudNotesService.instance.upsert(AuthService.instance.ownerKey, updated);
    }
  }

  Future<void> _syncReminder(Note note) async {
    try {
      if (note.reminderDate != null) {
        await NotificationService.instance.scheduleForNote(
          noteId: note.id,
          title: note.title,
          body: note.preview,
          when: note.reminderDate!,
        );
      } else {
        await NotificationService.instance.cancelForNote(note.id);
      }
    } catch (e) {
      debugPrint('reminder sync: $e');
    }
  }

  Future<void> _persist(List<Note> list, String key) async {
    notes.value = list;
    await StorageService.instance.saveNotes(key, list);
  }

  Future<void> _persistSections(List<NoteSection> list, String key) async {
    sections.value = list;
    await StorageService.instance.saveSections(key, list);
  }

  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return activeSorted;
    return activeSorted.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q);
    }).toList();
  }
}
