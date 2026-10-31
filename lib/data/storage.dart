import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/note.dart';

/// Локальное хранилище: настройки + разделы + заметки (local-first).
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kOnboardingDone = 'onboarding_done';
  static const _kThemeId = 'theme_id';
  static const _kBgId = 'bg_id';
  static const _kOwnerKey = 'owner_key';
  static const _kMode = 'app_mode'; // guest | cloud
  static const _kPremium = 'premium_active';
  static const _kNotesPrefix = 'notes_v1_';
  static const _kSectionsPrefix = 'sections_v1_';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Settings ──────────────────────────────────────────────
  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboardingDone, true);

  String get themeId => _prefs.getString(_kThemeId) ?? 'night';
  Future<void> setThemeId(String id) => _prefs.setString(_kThemeId, id);

  /// По умолчанию — «Бумага», чтобы сразу было видно изображение.
  String get bgId => _prefs.getString(_kBgId) ?? 'classic';
  Future<void> setBgId(String id) => _prefs.setString(_kBgId, id);

  String? get customBgPath => _prefs.getString('custom_bg_path');
  Future<void> setCustomBgPath(String path) =>
      _prefs.setString('custom_bg_path', path);
  Future<void> clearCustomBgPath() => _prefs.remove('custom_bg_path');

  /// Копирует выбранное фото в постоянное хранилище приложения.
  /// image_picker отдаёт временный путь — он пропадает после чистки кэша.
  Future<String?> persistBackgroundImage(File source) async {
    try {
      if (!await source.exists()) return null;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/backgrounds');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Очищаем старые кастомные фоны, кроме текущего.
      final current = customBgPath;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path != current) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      final ext = source.path.contains('.')
          ? source.path.split('.').last.toLowerCase()
          : 'jpg';
      final dest = File('${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await source.copy(dest.path);
      return dest.path;
    } catch (e) {
      return null;
    }
  }

  String get ownerKey => _prefs.getString(_kOwnerKey) ?? 'guest';
  Future<void> setOwnerKey(String key) => _prefs.setString(_kOwnerKey, key);

  String get mode => _prefs.getString(_kMode) ?? 'guest';
  Future<void> setMode(String mode) => _prefs.setString(_kMode, mode);

  bool get premiumActive => _prefs.getBool(_kPremium) ?? false;
  Future<void> setPremiumActive(bool v) => _prefs.setBool(_kPremium, v);

  // ── REST-сессия (для платформ без Firebase SDK, Windows) ──
  static const _kRestSession = 'rest_session_v1';

  Map<String, dynamic>? get restSession {
    final raw = _prefs.getString(_kRestSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> setRestSession(Map<String, dynamic>? value) async {
    if (value == null) {
      await _prefs.remove(_kRestSession);
      return;
    }
    await _prefs.setString(_kRestSession, jsonEncode(value));
  }

  // ── Notes (per owner) ─────────────────────────────────────
  String _notesKey(String ownerKey) => '$_kNotesPrefix$ownerKey';
  String _sectionsKey(String ownerKey) => '$_kSectionsPrefix$ownerKey';

  Future<List<Note>> loadNotes(String ownerKey) async {
    final raw = _prefs.getString(_notesKey(ownerKey));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotes(String ownerKey, List<Note> notes) async {
    final raw = jsonEncode(notes.map((n) => n.toJson()).toList());
    await _prefs.setString(_notesKey(ownerKey), raw);
  }

  Future<List<NoteSection>> loadSections(String ownerKey) async {
    final raw = _prefs.getString(_sectionsKey(ownerKey));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NoteSection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSections(String ownerKey, List<NoteSection> sections) async {
    final raw = jsonEncode(sections.map((s) => s.toJson()).toList());
    await _prefs.setString(_sectionsKey(ownerKey), raw);
  }

  Future<List<Note>> loadGuestNotes() => loadNotes('guest');

  /// Не удаляем заметки при выходе — пользователь чистит сам.
  Future<void> clearOwnerNotes(String ownerKey) async {
    await _prefs.remove(_notesKey(ownerKey));
    await _prefs.remove(_sectionsKey(ownerKey));
  }

  /// Слияние гостевых заметок и разделов с аккаунтом (без удаления).
  Future<List<Note>> migrateGuestNotesTo(String newOwnerKey) async {
    final guestNotes = await loadGuestNotes();
    final guestSections = await loadSections('guest');
    if (guestNotes.isEmpty && guestSections.isEmpty) {
      return loadNotes(newOwnerKey);
    }

    // Разделы: добавляем недостающие.
    final existingSections = await loadSections(newOwnerKey);
    final sectionIds = existingSections.map((e) => e.id).toSet();
    final mergedSections = [...existingSections];
    for (final s in guestSections) {
      if (!sectionIds.contains(s.id)) {
        mergedSections.add(s.copyWith(ownerKey: newOwnerKey));
        sectionIds.add(s.id);
      }
    }
    await saveSections(newOwnerKey, mergedSections);

    // Заметки: добавляем недостающие / берём более свежие.
    final existingNotes = await loadNotes(newOwnerKey);
    final map = {for (final n in existingNotes) n.id: n};
    for (final g in guestNotes) {
      final fixed = g.copyWith(ownerKey: newOwnerKey);
      final local = map[g.id];
      if (local == null) {
        map[g.id] = fixed;
      } else if (g.updatedAt.isAfter(local.updatedAt)) {
        map[g.id] = fixed;
      }
    }
    final merged = map.values.toList();
    await saveNotes(newOwnerKey, merged);

    // Гостевые данные оставляем на устройстве (на случай отката),
    // но очищаем, чтобы не дублировались при повторном входе.
    await clearOwnerNotes('guest');
    return merged;
  }

  /// При выходе из аккаунта копируем заметки в гостевое хранилище,
  /// чтобы они остались на устройстве.
  Future<void> copyOwnerNotesToGuest(String ownerKey) async {
    if (ownerKey == 'guest') return;
    final notes = await loadNotes(ownerKey);
    final sections = await loadSections(ownerKey);

    final guestNotes = await loadGuestNotes();
    final guestSections = await loadSections('guest');

    final noteIds = guestNotes.map((e) => e.id).toSet();
    final mergedNotes = [...guestNotes];
    for (final n in notes) {
      if (!noteIds.contains(n.id)) {
        mergedNotes.add(n.copyWith(ownerKey: 'guest'));
      }
    }

    final sectionIds = guestSections.map((e) => e.id).toSet();
    final mergedSections = [...guestSections];
    for (final s in sections) {
      if (!sectionIds.contains(s.id)) {
        mergedSections.add(s.copyWith(ownerKey: 'guest'));
      }
    }

    await saveNotes('guest', mergedNotes);
    await saveSections('guest', mergedSections);
  }
}
