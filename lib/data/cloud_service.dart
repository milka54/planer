import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/foundation.dart';

import 'firebase_rest.dart';
import 'models/note.dart';
import 'models/standalone_reminder.dart';

/// Асинхронная репликация заметок и разделов в Firestore.
class CloudNotesService {
  CloudNotesService._();
  static final CloudNotesService instance = CloudNotesService._();

  bool get _available {
    try {
      fs.FirebaseFirestore.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Платформы без Firebase SDK (Windows/desktop) работают через REST:
  /// тот же проект и те же данные, что и на телефоне.
  bool get _useRest => !_available && FirebaseRest.instance.isSignedIn;

  fs.CollectionReference<Map<String, dynamic>> _col(String uid) =>
      fs.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notes');

  /// Повтор при сетевых сбоях: облачная запись не должна теряться молча.
  Future<T?> _withRetry<T>(
    String label,
    Future<T> Function() body, {
    int attempts = 3,
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        return await body();
      } catch (e) {
        if (i == attempts - 1) {
          debugPrint('cloud $label (final): $e');
          return null;
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
      }
    }
    return null;
  }

  Future<void> upsert(String uid, Note note) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.pushNote(note);
      } catch (e) {
        debugPrint('rest upsert: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('upsert', () async {
      await _col(uid).doc(note.id).set(note.toFirestore());
    });
  }

  Future<void> delete(String uid, String noteId) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.delete('notes', noteId);
      } catch (e) {
        debugPrint('rest delete: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('delete', () async {
      await _col(uid).doc(noteId).delete();
    });
  }

  Future<void> pushAll(String uid, List<Note> notes) async {
    if (_useRest) {
      for (final n in notes) {
        try {
          await FirebaseRest.instance.pushNote(n);
        } catch (e) {
          debugPrint('rest pushAll: $e');
        }
      }
      return;
    }
    if (!_available || notes.isEmpty) return;
    await _withRetry('pushAll', () async {
      final batch = fs.FirebaseFirestore.instance.batch();
      final col = _col(uid);
      for (final n in notes) {
        batch.set(col.doc(n.id), n.toFirestore());
      }
      await batch.commit();
    });
  }

  Future<List<Note>?> pullAll(String uid) async {
    if (_useRest) {
      try {
        return await FirebaseRest.instance.pullNotes();
      } catch (e) {
        debugPrint('rest pullAll: $e');
        return null;
      }
    }
    if (!_available) return null;
    return _withRetry('pullAll', () async {
      final snap = await _col(uid).get();
      return snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return Note.fromFirestore(data);
      }).toList();
    });
  }

  // ── Разделы ───────────────────────────────────────────────

  fs.CollectionReference<Map<String, dynamic>> _secCol(String uid) =>
      fs.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sections');

  Future<void> upsertSection(String uid, NoteSection section) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.pushNoteSection(section);
      } catch (e) {
        debugPrint('rest upsertSection: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('upsertSection', () async {
      await _secCol(uid).doc(section.id).set(section.toFirestore());
    });
  }

  Future<void> deleteSection(String uid, String sectionId) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.delete('sections', sectionId);
      } catch (e) {
        debugPrint('rest deleteSection: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('deleteSection', () async {
      await _secCol(uid).doc(sectionId).delete();
    });
  }

  /// Полная выгрузка разделов: чинит облако, если разделы раньше
  /// не доехали из-за молчаливого сбоя записи.
  Future<void> pushAllSections(String uid, List<NoteSection> sections) async {
    if (_useRest) {
      for (final s in sections) {
        try {
          await FirebaseRest.instance.pushNoteSection(s);
        } catch (e) {
          debugPrint('rest pushAllSections: $e');
        }
      }
      return;
    }
    if (!_available || sections.isEmpty) return;
    await _withRetry('pushAllSections', () async {
      final batch = fs.FirebaseFirestore.instance.batch();
      final col = _secCol(uid);
      for (final s in sections) {
        batch.set(col.doc(s.id), s.toFirestore());
      }
      await batch.commit();
    });
  }

  Future<List<NoteSection>?> pullSections(String uid) async {
    if (_useRest) {
      try {
        return await FirebaseRest.instance.pullNoteSections();
      } catch (e) {
        debugPrint('rest pullSections: $e');
        return null;
      }
    }
    if (!_available) return null;
    return _withRetry('pullSections', () async {
      final snap = await _secCol(uid).get();
      return snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return NoteSection.fromFirestore(data);
      }).toList();
    });
  }

  // ── Напоминания и их разделы ──────────────────────────────

  fs.CollectionReference<Map<String, dynamic>> _remCol(String uid) =>
      fs.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders');

  fs.CollectionReference<Map<String, dynamic>> _remSecCol(String uid) =>
      fs.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminder_sections');

  Future<void> upsertReminder(String uid, StandaloneReminder r) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.pushReminder(r);
      } catch (e) {
        debugPrint('rest upsertReminder: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('upsertReminder', () async {
      await _remCol(uid).doc(r.id).set(r.toFirestore());
    });
  }

  Future<void> deleteReminder(String uid, String id) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.delete('reminders', id);
      } catch (e) {
        debugPrint('rest deleteReminder: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('deleteReminder', () async {
      await _remCol(uid).doc(id).delete();
    });
  }

  Future<void> pushAllReminders(String uid, List<StandaloneReminder> list) async {
    if (_useRest) {
      for (final r in list) {
        try {
          await FirebaseRest.instance.pushReminder(r);
        } catch (e) {
          debugPrint('rest pushAllReminders: $e');
        }
      }
      return;
    }
    if (!_available || list.isEmpty) return;
    await _withRetry('pushAllReminders', () async {
      final batch = fs.FirebaseFirestore.instance.batch();
      final col = _remCol(uid);
      for (final r in list) {
        batch.set(col.doc(r.id), r.toFirestore());
      }
      await batch.commit();
    });
  }

  Future<List<StandaloneReminder>?> pullReminders(String uid) async {
    if (_useRest) {
      try {
        return await FirebaseRest.instance.pullReminders();
      } catch (e) {
        debugPrint('rest pullReminders: $e');
        return null;
      }
    }
    if (!_available) return null;
    return _withRetry('pullReminders', () async {
      final snap = await _remCol(uid).get();
      return snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return StandaloneReminder.fromFirestore(data);
      }).toList();
    });
  }

  Future<void> upsertReminderSection(String uid, ReminderSection s) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.pushReminderSection(s);
      } catch (e) {
        debugPrint('rest upsertReminderSection: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('upsertReminderSection', () async {
      await _remSecCol(uid).doc(s.id).set(s.toFirestore());
    });
  }

  Future<void> deleteReminderSection(String uid, String id) async {
    if (_useRest) {
      try {
        await FirebaseRest.instance.delete('reminder_sections', id);
      } catch (e) {
        debugPrint('rest deleteReminderSection: $e');
      }
      return;
    }
    if (!_available) return;
    await _withRetry('deleteReminderSection', () async {
      await _remSecCol(uid).doc(id).delete();
    });
  }

  Future<void> pushAllReminderSections(
    String uid,
    List<ReminderSection> list,
  ) async {
    if (_useRest) {
      for (final s in list) {
        try {
          await FirebaseRest.instance.pushReminderSection(s);
        } catch (e) {
          debugPrint('rest pushAllReminderSections: $e');
        }
      }
      return;
    }
    if (!_available || list.isEmpty) return;
    await _withRetry('pushAllReminderSections', () async {
      final batch = fs.FirebaseFirestore.instance.batch();
      final col = _remSecCol(uid);
      for (final s in list) {
        batch.set(col.doc(s.id), s.toFirestore());
      }
      await batch.commit();
    });
  }

  Future<List<ReminderSection>?> pullReminderSections(String uid) async {
    if (_useRest) {
      try {
        return await FirebaseRest.instance.pullReminderSections();
      } catch (e) {
        debugPrint('rest pullReminderSections: $e');
        return null;
      }
    }
    if (!_available) return null;
    return _withRetry('pullReminderSections', () async {
      final snap = await _remSecCol(uid).get();
      return snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return ReminderSection.fromFirestore(data);
      }).toList();
    });
  }
}
