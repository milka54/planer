import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:planer/data/backup_service.dart';
import 'package:planer/data/models/note.dart';
import 'package:planer/data/models/standalone_reminder.dart';
import 'package:planer/data/notes_repository.dart';
import 'package:planer/data/reminder_service.dart';
import 'package:planer/data/storage.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('planer_backup_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('экспорт → импорт: заметки, фото, напоминания восстанавливаются',
      () async {
    // Подготовка: файл вложения + заметка с фото и голосом.
    final img = File('${tmp.path}/photo.jpg');
    await img.writeAsBytes(List.filled(64, 7));

    final section = await NotesRepository.instance
        .createSection(title: 'Работа');
    final note = await NotesRepository.instance.create(
      title: 'Встреча',
      content: 'Обсудить смету',
      sectionId: section.id,
      imagePaths: [img.path],
      voicePaths: [],
    );
    final rsec = await ReminderService.instance
        .createSection(title: 'Дни рождения');
    await ReminderService.instance.add(
      StandaloneReminder.create(
        title: 'Маме',
        fireAt: DateTime.now().add(const Duration(days: 30)),
        sectionId: rsec.id,
        repeatType: StandaloneReminder.repeatYearly,
      ),
    );

    final zip = await BackupService.instance.buildBackupBytes();
    expect(zip, isNotEmpty);

    // «Новое устройство»: чистим память репозиториев.
    NotesRepository.instance.notes.value = [];
    NotesRepository.instance.sections.value = [];
    ReminderService.instance.reminders.value = [];
    ReminderService.instance.sections.value = [];

    final attachDir = Directory('${tmp.path}/imported_attachments');
    final summary = await BackupService.instance.importBackupBytes(
      zip,
      attachmentsDir: attachDir,
    );

    expect(summary.notes, 1); // 1 заметка + 1 раздел не считается
    expect(summary.reminders, 1);

    final restored = NotesRepository.instance.all.single;
    expect(restored.id, note.id);
    expect(restored.title, 'Встреча');
    expect(restored.sectionId, section.id);
    expect(restored.imagePaths, hasLength(1));
    expect(File(restored.imagePaths.single).existsSync(), isTrue);
    expect(restored.imagePaths.single, contains('imported_attachments'));

    final rem = ReminderService.instance.reminders.value.single;
    expect(rem.title, 'Маме');
    expect(rem.repeatType, StandaloneReminder.repeatYearly);
    expect(ReminderService.instance.allSections.single.title, 'Дни рождения');

    // Повторный импорт идемпотентен: ничего не изменилось.
    final again = await BackupService.instance.importBackupBytes(
      zip,
      attachmentsDir: attachDir,
    );
    expect(again.notes, 0);
    expect(again.reminders, 0);
    expect(NotesRepository.instance.all, hasLength(1));
    expect(ReminderService.instance.reminders.value, hasLength(1));
  });
}
