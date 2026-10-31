import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/family_space.dart';

/// Удаление пространства создателем и выход участника.
void main() {
  test('delete space: only creator; leave: any member', () async {
    final a = FirebaseRest.instance;
    const pass = 'restTest2026';

    // A создаёт пространство.
    await a.signIn('planer-rest-test-2026@example.com', pass);
    final uidA = a.uid!;
    final space = FamilySpace.create(name: 'Права-тест', createdBy: uidA);
    await a.upsertPath('family_spaces', space.id, space.toFirestore());
    await a.pushSpaceDoc(space.id, 'members', uidA, FamilyMember(
      uid: uidA,
      email: a.email!,
      displayName: 'A',
      role: 'owner',
      joinedAt: DateTime.now(),
    ).toFirestore());

    // Генерируем код, чтобы B мог вступить.
    final token = 'plnperm_${DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF}';
    await a.upsertPath('join_codes', token, {
      'token': token,
      'spaceId': space.id,
      'spaceName': space.name,
      'createdBy': uidA,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await a.signOut();

    // B вступает.
    await a.signIn('planer-rest-test2-2026@example.com', pass);
    final uidB = a.uid!;
    final memberB = FamilyMember(
      uid: uidB,
      email: a.email!,
      displayName: 'B',
      role: 'member',
      joinedAt: DateTime.now(),
    );
    final dataB = memberB.toFirestore()..['joinToken'] = token;
    await a.pushSpaceDoc(space.id, 'members', uidB, dataB);

    // 1. Участник НЕ может удалить пространство.
    var denied = false;
    try {
      await a.deletePath('family_spaces', space.id);
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'участник не должен удалять пространство');
    print('B: delete space denied OK');

    // 2. Участник может выйти — его карточка удаляется.
    // Состав проверяем ДО выхода (после него доступ закрыт).
    final membersBefore = await a.pullSpaceCollection(space.id, 'members');
    expect(membersBefore.any((m) => m['uid'] == uidB), isTrue);
    await a.removeSpaceDoc(space.id, 'members', uidB);
    print('B: leave space OK');

    // После выхода пространство недоступно.
    denied = false;
    try {
      await a.getDoc('family_spaces/${space.id}');
    } catch (e) {
      denied = '$e'.contains('permission') || '$e'.contains('Missing');
    }
    expect(denied, isTrue,
        reason: 'после выхода доступ к пространству должен закрыться');
    print('B: access after leave closed OK');
    await a.signOut();

    // 3. Создатель удаляет пространство — ему можно.
    await a.signIn('planer-rest-test-2026@example.com', pass);
    await a.deletePath('family_spaces', space.id);
    print('A: delete space as creator OK');
    await a.signOut();

    print('PERMISSIONS: ALL OK');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
