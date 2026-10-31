import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/family_space.dart';
import 'package:planer/data/models/note.dart';

/// Сквозная проверка: безопасность групп + синхронизация задач.
/// Два аккаунта по очереди (FirebaseRest — синглтон).
void main() {
  final a = FirebaseRest.instance;
  const emailA = 'planer-rest-test-2026@example.com';
  const emailB = 'planer-rest-test2-2026@example.com';
  const pass = 'restTest2026';

  test('Security + sync: invite-only access, done-status, deletion', () async {
    // ── Устройство A: создаёт пространство, задачу, код-ссылку ──
    await a.signIn(emailA, pass);
    final uidA = a.uid!;
    print('A uid=$uidA');

    final space = FamilySpace.create(name: 'Проверка-группа', createdBy: uidA);
    await a.upsertPath('family_spaces', space.id, space.toFirestore());
    final ownerA = FamilyMember(
      uid: uidA,
      email: emailA,
      displayName: 'UserA',
      firstName: 'User',
      lastName: 'A',
      role: 'owner',
      joinedAt: DateTime.now(),
    );
    await a.pushSpaceDoc(space.id, 'members', uidA, ownerA.toFirestore());

    final task = FamilyNote.create(
      title: 'Совместная задача',
      content: 'проверка синхронизации',
      ownerUid: uidA,
    );
    await a.pushSpaceDoc(space.id, 'notes', task.id, task.toFirestore());

    // Код-ссылка.
    final token = 'plntest_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    await a.upsertPath('join_codes', token, {
      'token': token,
      'spaceId': space.id,
      'spaceName': space.name,
      'createdBy': uidA,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    print('A: space ${space.id}, task ${task.id}, token $token');
    await a.signOut();

    // ── Устройство B: проверка изоляции и вступления ──
    try {
      await a.signIn(emailB, pass);
    } catch (_) {
      await a.register(emailB, pass);
    }
    final uidB = a.uid!;
    print('B uid=$uidB');

    // 1. Без вступления доступ к пространству ЗАКРЫТ.
    var denied = false;
    try {
      await a.getDoc('family_spaces/${space.id}');
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'non-member must NOT read the space doc');
    print('B: space doc read denied OK');

    denied = false;
    try {
      await a.pullSpaceCollection(space.id, 'notes');
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'non-member must NOT read space notes');
    print('B: space notes read denied OK');

    // 2. Вступить просто по id пространства (без токена) — НЕЛЬЗЯ.
    final bogusMember = FamilyMember(
      uid: uidB,
      email: emailB,
      displayName: 'Hacker',
      role: 'member',
      joinedAt: DateTime.now(),
    );
    denied = false;
    try {
      await a.pushSpaceDoc(space.id, 'members', uidB, bogusMember.toFirestore());
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'join without token/invite must be rejected');
    print('B: join without token denied OK');

    // 3. Чужие личные заметки недоступны.
    denied = false;
    try {
      await a.fetchAll('notes');
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    // fetchAll идёт в users/$uid/notes самого B — это должно работать.
    expect(denied, isFalse,
        reason: 'user must read their OWN notes');
    print('B: own notes read OK');

    denied = false;
    try {
      // Прямой путь к личным данным A.
      await a.getDoc('users/$uidA/notes/${task.id}');
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'user must NOT read another users private notes');
    print('B: foreign private notes denied OK');

    // 4. Вступление по коду-ссылке — РАБОТАЕТ.
    final joinData = await a.getDoc('join_codes/$token');
    expect(joinData, isNotNull, reason: 'join code must be readable');
    expect(joinData!['spaceId'], space.id);

    final memberB = FamilyMember(
      uid: uidB,
      email: emailB,
      displayName: 'UserB',
      firstName: 'User',
      lastName: 'B',
      role: 'member',
      joinedAt: DateTime.now(),
    );
    final dataB = memberB.toFirestore();
    dataB['joinToken'] = token; // без него правила не пустят
    await a.pushSpaceDoc(space.id, 'members', uidB, dataB);
    print('B: joined via token OK');

    // 5. Теперь доступ есть.
    final spaceDoc = await a.getDoc('family_spaces/${space.id}');
    expect(spaceDoc, isNotNull);
    var notes = await a.pullSpaceCollection(space.id, 'notes');
    expect(notes.any((n) => n['id'] == task.id), isTrue,
        reason: 'member must see shared tasks');
    print('B: sees shared tasks OK');

    // 6. B отмечает задачу выполненной.
    final doneTask = FamilyNote.fromMap({
      ...notes.firstWhere((n) => n['id'] == task.id),
      'done': true,
      'doneBy': uidB,
      'doneAt': DateTime.now().millisecondsSinceEpoch,
      'updatedBy': uidB,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await a.pushSpaceDoc(space.id, 'notes', doneTask.id, doneTask.toFirestore());
    print('B: marked task done');

    // 6b. Удалить чужую задачу B НЕ может (только создатель).
    denied = false;
    try {
      await a.removeSpaceDoc(space.id, 'notes', task.id);
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'only the task creator may delete it');
    print('B: delete foreign task denied OK');
    await a.signOut();

    // ── A видит, что задача выполнена ──
    await a.signIn(emailA, pass);
    notes = await a.pullSpaceCollection(space.id, 'notes');
    final seen = notes.firstWhere((n) => n['id'] == task.id);
    expect(seen['done'], isTrue,
        reason: 'done-status must sync to the other user');
    print('A: sees done=true OK');

    // 7. A удаляет задачу, фиксируя, что она была выполнена.
    await a.removeSpaceDoc(space.id, 'notes', task.id);
    await a.pushSpaceDoc(space.id, 'deletions', task.id, {
      'noteId': task.id,
      'title': task.title,
      'deletedBy': uidA,
      'deletedByName': 'UserA',
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
      'wasDone': true,
    });
    print('A: deleted task with wasDone=true');
    await a.signOut();

    // ── B видит удаление ──
    await a.signIn(emailB, pass);
    notes = await a.pullSpaceCollection(space.id, 'notes');
    expect(notes.any((n) => n['id'] == task.id), isFalse,
        reason: 'deleted task must disappear for other users');
    final tombs = await a.pullSpaceCollection(space.id, 'deletions');
    final tomb = tombs.firstWhere((t) => (t['noteId'] ?? t['id']) == task.id);
    expect(tomb['wasDone'], isTrue);
    expect(tomb['deletedByName'], 'UserA');
    print('B: deletion tombstone with wasDone OK');

    // 8. B — участник, но C (новый пользователь) не должен видеть группу.
    await a.signOut();
    try {
      await a.signIn('planer-rest-test3-2026@example.com', pass);
    } catch (_) {
      await a.register('planer-rest-test3-2026@example.com', pass);
    }
    denied = false;
    try {
      await a.getDoc('family_spaces/${space.id}');
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'third user must NOT see the group');
    print('C: group invisible OK');
    await a.signOut();

    print('SECURITY + SYNC: ALL OK');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
