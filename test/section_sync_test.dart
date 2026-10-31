import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/note.dart';

void main() {
  test('REST roundtrip: sections + notes with sectionId', () async {
    final rest = FirebaseRest.instance;
    const email = 'planer-rest-test-2026@example.com';
    const password = 'restTest2026';
    await rest.signIn(email, password);
    print('signed in uid=${rest.uid}');
    expect(rest.isSignedIn, isTrue);

    final sec = NoteSection.create(
      title: 'Тестовый раздел',
      ownerKey: rest.uid!,
      colorIndex: 2,
    );
    await rest.pushNoteSection(sec);
    print('pushed section id=${sec.id}');

    final note = Note.create(
      title: 'Заметка в разделе',
      content: 'тест',
      ownerKey: rest.uid!,
      sectionId: sec.id,
      colorIndex: 1,
    );
    await rest.pushNote(note);
    print('pushed note id=${note.id} sectionId=${note.sectionId}');

    final secs = await rest.pullNoteSections();
    print('pulled sections: ${secs.length}');
    for (final s in secs) {
      print('  sec: id=${s.id} title=${s.title} color=${s.colorIndex}');
    }
    expect(secs.any((s) => s.id == sec.id && s.title == 'Тестовый раздел'),
        isTrue,
        reason: 'section must roundtrip through REST');

    final notes = await rest.pullNotes();
    final pulled = notes.where((n) => n.id == note.id).toList();
    print('pulled notes: ${notes.length}, matching: ${pulled.length}');
    expect(pulled, hasLength(1));
    expect(pulled.first.sectionId, sec.id,
        reason: 'sectionId must survive REST');

    await rest.delete('notes', note.id);
    await rest.delete('sections', sec.id);
    print('cleanup OK');
    await rest.signOut();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
