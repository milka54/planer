import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/note.dart';
import 'package:planer/data/models/standalone_reminder.dart';

/// Симуляция двух устройств: A пишет, B (другая "сессия") читает.
void main() {
  test('Cross-device sync: sections + notes + reminders', () async {
    final a = FirebaseRest.instance;
    await a.signIn('planer-rest-test-2026@example.com', 'restTest2026');
    final uid = a.uid!;
    print('device A uid=$uid');

    // ── Устройство A создаёт разделы и контент ──
    final sec = NoteSection.create(title: 'Работа', ownerKey: uid, colorIndex: 3);
    final sec2 = NoteSection.create(title: 'Дом', ownerKey: uid, colorIndex: 1);
    await a.pushNoteSection(sec);
    await a.pushNoteSection(sec2);

    final n1 = Note.create(
        title: 'Отчёт', content: 'сдать до пятницы', ownerKey: uid, sectionId: sec.id);
    final n2 = Note.create(
        title: 'Купить хлеб', content: '', ownerKey: uid, sectionId: sec2.id);
    final n3 = Note.create(title: 'Без раздела', content: '', ownerKey: uid);
    await a.pushNote(n1);
    await a.pushNote(n2);
    await a.pushNote(n3);

    final rsec = ReminderSection.create(title: 'Дни рождения', ownerKey: uid);
    await a.pushReminderSection(rsec);
    final rem = StandaloneReminder.create(
      title: 'День рождения мамы',
      fireAt: DateTime.now().add(const Duration(days: 30)),
      ownerKey: uid,
      sectionId: rsec.id,
      repeatType: StandaloneReminder.repeatYearly,
      body: 'позвонить и поздравить',
    );
    await a.pushReminder(rem);
    print('device A pushed: 2 sections, 3 notes, 1 reminder section, 1 yearly reminder');

    // ── Устройство B: чистая сессия, только вход ──
    await a.signOut();
    final b = FirebaseRest.instance;
    await b.signIn('planer-rest-test-2026@example.com', 'restTest2026');
    print('device B uid=${b.uid}');

    final secs = await b.pullNoteSections();
    final notes = await b.pullNotes();
    final rems = await b.pullReminders();
    final rsecs = await b.pullReminderSections();
    print('device B pulled: ${secs.length} sections, ${notes.length} notes, '
        '${rsecs.length} reminder_sections, ${rems.length} reminders');

    // Разделы доехали с названиями
    final secById = {for (final s in secs) s.id: s};
    expect(secById[sec.id]?.title, 'Работа', reason: 'section A must arrive');
    expect(secById[sec2.id]?.title, 'Дом', reason: 'section B must arrive');

    // Заметки доехали с привязкой к разделам
    final noteById = {for (final n in notes) n.id: n};
    expect(noteById[n1.id]?.sectionId, sec.id);
    expect(noteById[n2.id]?.sectionId, sec2.id);
    expect(noteById[n3.id]?.sectionId, isNull);
    // Раздел, к которому привязана заметка, существует
    expect(secById.containsKey(noteById[n1.id]!.sectionId), isTrue,
        reason: 'note must not be orphaned');

    // Напоминания: раздел + ежегодное с описанием
    expect(rsecs.any((s) => s.id == rsec.id && s.title == 'Дни рождения'), isTrue);
    final pulledRem = rems.firstWhere((r) => r.id == rem.id);
    expect(pulledRem.title, 'День рождения мамы');
    expect(pulledRem.body, 'позвонить и поздравить');
    expect(pulledRem.yearly, isTrue);
    expect(pulledRem.sectionId, rsec.id);

    print('CROSS-DEVICE SYNC: OK');

    // cleanup
    await b.delete('notes', n1.id);
    await b.delete('notes', n2.id);
    await b.delete('notes', n3.id);
    await b.delete('sections', sec.id);
    await b.delete('sections', sec2.id);
    await b.delete('reminders', rem.id);
    await b.delete('reminder_sections', rsec.id);
    await b.signOut();
    print('cleanup OK');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
