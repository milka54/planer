import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/family_space.dart';

void main() {
  test('Family spaces: create space + note + message + invite', () async {
    final rest = FirebaseRest.instance;
    await rest.signIn('planer-rest-test-2026@example.com', 'restTest2026');
    final uid = rest.uid!;
    final email = rest.email!;
    print('uid=$uid email=$email');

    final space = FamilySpace.create(name: 'Тест-семья', createdBy: uid);
    await rest.upsertPath('family_spaces', space.id, space.toFirestore());
    print('space created ${space.id}');

    final owner = FamilyMember(
      uid: uid,
      email: email,
      displayName: 'tester',
      role: 'owner',
      joinedAt: DateTime.now(),
    );
    await rest.pushSpaceDoc(space.id, 'members', uid, owner.toFirestore());

    final note = FamilyNote.create(
      title: 'Купить продукты',
      content: 'молоко, хлеб',
      ownerUid: uid,
    );
    await rest.pushSpaceDoc(space.id, 'notes', note.id, note.toFirestore());

    final msg = FamilyMessage.create(
      text: 'Привет семья!',
      senderUid: uid,
      senderEmail: email,
      senderName: 'tester',
    );
    await rest.pushSpaceDoc(space.id, 'messages', msg.id, msg.toFirestore());

    final invite = FamilyInvite(
      email: 'member@example.com',
      spaceId: space.id,
      spaceName: space.name,
      invitedBy: email,
      status: 'pending',
      createdAt: DateTime.now(),
    );
    await rest.pushSpaceDoc(space.id, 'invites', invite.email, invite.toFirestore());
    await rest.pushMailboxInvite('member@example.com', space.id, invite.toFirestore());

    // Проверяем чтение
    final spaceDoc = await rest.getDoc('family_spaces/${space.id}');
    expect(spaceDoc, isNotNull);
    expect(spaceDoc!['name'], 'Тест-семья');
    print('read space doc OK');

    List<Map<String, dynamic>> members;
    try {
      members = await rest.pullSpaceCollection(space.id, 'members');
      print('read members OK: ${members.length}');
    } catch (e) {
      print('read members FAIL: $e');
      rethrow;
    }
    expect(members.any((m) => m['uid'] == uid), isTrue);

    try {
      final notes = await rest.pullSpaceCollection(space.id, 'notes');
      print('read notes OK: ${notes.length}');
      expect(notes.any((n) => n['title'] == 'Купить продукты'), isTrue);
    } catch (e) {
      print('read notes FAIL: $e');
      rethrow;
    }

    try {
      final msgs = await rest.pullSpaceCollection(space.id, 'messages');
      print('read messages OK: ${msgs.length}');
      expect(msgs.any((m) => m['text'] == 'Привет семья!'), isTrue);
    } catch (e) {
      print('read messages FAIL: $e');
      rethrow;
    }

    // Приглашение видно владельцу в пространстве (чужой ящик закрыт).
    final spaceInvites = await rest.pullSpaceCollection(space.id, 'invites');
    print('read space invites OK: ${spaceInvites.length}');
    expect(spaceInvites.any((i) => i['email'] == 'member@example.com'), isTrue);

    // Владелец читает СВОЙ почтовый ящик (так делает приложение).
    final myInbox = await rest.pullMailboxInvites(rest.email!);
    print('read own mailbox OK: ${myInbox.length}');

    print('FAMILY SPACES: OK');

    // cleanup: сначала то, где нужен isOwner (пока member-doc жив),
    // member-doc удаляем последним — на него правило по uid.
    await rest.removeSpaceDoc(space.id, 'notes', note.id);
    await rest.removeSpaceDoc(space.id, 'messages', msg.id);
    await rest.removeSpaceDoc(space.id, 'invites', 'member@example.com');
    await rest.removeMailboxInvite('member@example.com', space.id);
    await rest.deletePath('family_spaces', space.id);
    await rest.removeSpaceDoc(space.id, 'members', uid);
    await rest.signOut();
    print('cleanup OK');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
