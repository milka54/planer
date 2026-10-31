import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/note.dart';
import 'package:planer/data/models/standalone_reminder.dart';

void main() {
  test('Diagnose Firestore rules per collection', () async {
    final rest = FirebaseRest.instance;
    await rest.signIn('planer-rest-test-2026@example.com', 'restTest2026');
    print('uid=${rest.uid}');

    Future<void> probe(String label, Future<void> Function() write,
        Future<void> Function() read) async {
      try {
        await write();
        print('WRITE $label: OK');
      } catch (e) {
        print('WRITE $label: FAIL — $e');
      }
      try {
        await read();
        print('READ  $label: OK');
      } catch (e) {
        print('READ  $label: FAIL — $e');
      }
    }

    final now = DateTime.now();
    final n = Note.create(title: 'probe', content: 'x', ownerKey: rest.uid!);
    final s = NoteSection.create(title: 'probe-sec', ownerKey: rest.uid!);
    final r = StandaloneReminder.create(
        title: 'probe-rem', fireAt: now.add(const Duration(hours: 1)), ownerKey: rest.uid!);
    final rs = ReminderSection.create(title: 'probe-rsec', ownerKey: rest.uid!);

    await probe('notes', () => rest.pushNote(n), () => rest.pullNotes());
    await probe('sections', () => rest.pushNoteSection(s), () => rest.pullNoteSections());
    await probe('reminders', () => rest.pushReminder(r), () => rest.pullReminders());
    await probe('reminder_sections', () => rest.pushReminderSection(rs), () => rest.pullReminderSections());

    // cleanup best-effort
    for (final c in ['notes', 'sections', 'reminders', 'reminder_sections']) {
      final id = {'notes': n.id, 'sections': s.id, 'reminders': r.id, 'reminder_sections': rs.id}[c]!;
      try { await rest.delete(c, id); } catch (_) {}
    }
    await rest.signOut();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
