import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'auth_service.dart';
import 'models/note.dart';
import 'models/standalone_reminder.dart';
import 'notes_repository.dart';
import 'reminder_service.dart';

/// Резервное копирование: zip с JSON (заметки/напоминания/разделы)
/// и файлами вложений (фото, голос). Импорт сливает данные с текущими.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _format = 'planer-backup';
  static const _version = 1;

  /// Собирает zip-байты резервной копии (JSON + вложения).
  Future<List<int>> buildBackupBytes() async {
    final notes = NotesRepository.instance.notes.value;
    final sections = NotesRepository.instance.allSections;
    final reminders = ReminderService.instance.reminders.value;
    final remSections = ReminderService.instance.allSections;

    final archive = Archive();
    final relByAbs = <String, String>{};
    var seq = 0;

    String relPath(String abs) {
      return relByAbs.putIfAbsent(abs, () {
        seq++;
        final name = abs.split(RegExp(r'[\\/]')).last;
        return 'attachments/${seq}_$name';
      });
    }

    final noteJson = notes.map((n) {
      final j = n.toJson();
      j['voicePaths'] = n.voicePaths.map(relPath).toList();
      j['imagePaths'] = n.imagePaths.map(relPath).toList();
      return j;
    }).toList();

    for (final entry in relByAbs.entries) {
      final f = File(entry.key);
      if (f.existsSync()) {
        archive.addFile(
          ArchiveFile(entry.value, f.lengthSync(), f.readAsBytesSync()),
        );
      }
    }

    final meta = <String, dynamic>{
      'format': _format,
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'ownerKey': AuthService.instance.ownerKey,
      'notes': noteJson,
      'sections': sections.map((s) => s.toJson()).toList(),
      'reminders': reminders.map((r) => r.toJson()).toList(),
      'reminderSections': remSections.map((s) => s.toJson()).toList(),
    };
    final metaBytes = utf8.encode(jsonEncode(meta));
    archive.addFile(ArchiveFile('planer-backup.json', metaBytes.length, metaBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw const FormatException('Не удалось собрать архив');
    return zipBytes;
  }

  /// Предлагает сохранить резервную копию.
  /// Возвращает путь к файлу или null (отмена).
  Future<String?> exportAll() async {
    final zipBytes = await buildBackupBytes();
    final name =
        'planer-backup-${_stamp(DateTime.now())}.zip';
    String? target;
    if (Platform.isAndroid || Platform.isIOS) {
      target = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: name,
        bytes: Uint8List.fromList(zipBytes),
      );
    } else {
      target = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: name,
      );
      if (target != null) {
        await File(target).writeAsBytes(zipBytes, flush: true);
      }
    }
    return target;
  }

  /// Читает zip-копию и сливает данные с текущими.
  /// Возвращает итог или null (отмена выбора файла).
  Future<({int notes, int reminders})?> importAll() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите резервную копию',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) throw const FormatException('Не удалось прочитать файл');
    return importBackupBytes(bytes);
  }

  /// Сливает данные из zip-байтов с текущими ([attachmentsDir] — куда
  /// складывать файлы вложений; по умолчанию — хранилище приложения).
  Future<({int notes, int reminders})> importBackupBytes(
    List<int> bytes, {
    Directory? attachmentsDir,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? metaFile;
    for (final f in archive.files) {
      if (f.isFile && f.name.endsWith('planer-backup.json')) {
        metaFile = f;
        break;
      }
    }
    if (metaFile == null) {
      throw const FormatException('В архиве нет planer-backup.json');
    }
    final metaRaw = metaFile.content;
    if (metaRaw is! List<int>) {
      throw const FormatException('Повреждённый planer-backup.json');
    }
    final meta =
        jsonDecode(utf8.decode(metaRaw)) as Map<String, dynamic>;
    if (meta['format'] != _format) {
      throw const FormatException('Неизвестный формат резервной копии');
    }

    // Извлекаем вложения в постоянное хранилище.
    Directory dir;
    if (attachmentsDir != null) {
      dir = attachmentsDir;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}/attachments');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    final absByRel = <String, String>{};
    var seq = 0;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('attachments/')) continue;
      seq++;
      final content = f.content;
      if (content is! List<int>) continue;
      final name = f.name.split('/').last;
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final dest = File(
        '${dir.path}/i_${DateTime.now().microsecondsSinceEpoch}_$seq$safe',
      );
      await dest.writeAsBytes(content, flush: true);
      absByRel[f.name] = dest.path;
    }

    List<String> restorePaths(dynamic raw) {
      return (raw as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .map((rel) => absByRel[rel] ?? rel)
          .where((p) => p.contains('/attachments/') || p.contains('attachments'))
          .toList();
    }

    final key = AuthService.instance.ownerKey;
    final incomingNotes = (meta['notes'] as List<dynamic>? ?? []).map((e) {
      final j = Map<String, dynamic>.from(e as Map);
      j['voicePaths'] = restorePaths(j['voicePaths']);
      j['imagePaths'] = restorePaths(j['imagePaths']);
      final n = Note.fromJson(j);
      return Note(
        id: n.id,
        title: n.title,
        content: n.content,
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
        reminderDate: n.reminderDate,
        colorIndex: n.colorIndex,
        pinned: n.pinned,
        archived: n.archived,
        ownerKey: key,
        sectionId: n.sectionId,
        voicePaths: n.voicePaths,
        imagePaths: n.imagePaths,
      );
    }).toList();

    final incomingSections =
        (meta['sections'] as List<dynamic>? ?? []).map((e) {
      final s = NoteSection.fromJson(Map<String, dynamic>.from(e as Map));
      return NoteSection(
        id: s.id,
        title: s.title,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        colorIndex: s.colorIndex,
        ownerKey: key,
      );
    }).toList();

    final incomingReminders =
        (meta['reminders'] as List<dynamic>? ?? []).map((e) {
      final r = StandaloneReminder.fromJson(Map<String, dynamic>.from(e as Map));
      return r.copyWith(ownerKey: key);
    }).toList();

    final incomingRemSections =
        (meta['reminderSections'] as List<dynamic>? ?? []).map((e) {
      final s = ReminderSection.fromJson(Map<String, dynamic>.from(e as Map));
      return ReminderSection(
        id: s.id,
        title: s.title,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        colorIndex: s.colorIndex,
        ownerKey: key,
      );
    }).toList();

    final notesChanged = await NotesRepository.instance.importBatch(
      incomingNotes: incomingNotes,
      incomingSections: incomingSections,
    );
    final remindersChanged = await ReminderService.instance.importBatch(
      incomingReminders: incomingReminders,
      incomingSections: incomingRemSections,
    );
    debugPrint('backup import: $notesChanged notes, $remindersChanged reminders');
    return (notes: notesChanged, reminders: remindersChanged);
  }

  static String _stamp(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${p(t.month)}${p(t.day)}-${p(t.hour)}${p(t.minute)}';
  }
}
