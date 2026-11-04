import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';

/// Фикс приглашений для пространств «старых версий»:
/// 1) владелец БЕЗ role в members-карточке может создать код-ссылку
///    (фолбэк isOwner → isSpaceCreator);
/// 2) посторонний не может создать код для чужого пространства;
/// 3) участник (role=member) может создать код (правило isMember);
/// 4) вступление по токену работает.
void main() {
  final a = FirebaseRest.instance;
  const emailA = 'planer-rest-test-2026@example.com';
  const emailB = 'planer-rest-test2-2026@example.com';
  const pass = 'restTest2026';

  test('legacy space: приглашения работают', () async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    await a.signIn(emailA, pass);
    final uidA = a.uid!;
    final spaceId = 'legacy_$ts';

    // Пространство «старой версии»: createdBy есть, role у владельца нет.
    await a.upsertPath('family_spaces', spaceId, {
      'id': spaceId,
      'name': 'Старое пространство',
      'createdBy': uidA,
      'createdAt': ts,
      'updatedAt': ts,
    });
    await a.pushSpaceDoc(spaceId, 'members', uidA, {
      'uid': uidA,
      'email': emailA,
      'displayName': 'UserA',
      'joinedAt': ts,
    });

    // 1) Владелец без role создаёт код — раньше падал с permission-denied.
    final token = 'plnleg${ts.toRadixString(36)}';
    await a.upsertPath('join_codes', token, {
      'token': token,
      'spaceId': spaceId,
      'spaceName': 'Старое пространство',
      'createdBy': uidA,
      'createdAt': ts,
    });
    final doc = await a.getDoc('join_codes/$token');
    expect(doc, isNotNull);
    print('1. legacy-владелец без role создал код: OK');

    // 2) Посторонний не может создать код для чужого пространства.
    await a.signIn(emailB, pass);
    final uidB = a.uid!;
    var denied = false;
    try {
      await a.upsertPath('join_codes', 'plnfor$ts', {
        'token': 'plnfor$ts',
        'spaceId': spaceId,
        'spaceName': 'Старое пространство',
        'createdBy': uidB,
        'createdAt': ts,
      });
    } catch (_) {
      denied = true;
    }
    expect(denied, isTrue, reason: 'посторонний не должен создавать коды');
    print('2. постороннему отказано: OK');

    // 3) B вступает по токену и может создавать свои коды (isMember).
    await a.pushSpaceDoc(spaceId, 'members', uidB, {
      'uid': uidB,
      'email': emailB,
      'displayName': 'UserB',
      'role': 'member',
      'joinedAt': DateTime.now().millisecondsSinceEpoch,
      'joinToken': token,
    });
    final token2 = 'plnmem${ts.toRadixString(36)}';
    await a.upsertPath('join_codes', token2, {
      'token': token2,
      'spaceId': spaceId,
      'spaceName': 'Старое пространство',
      'createdBy': uidB,
      'createdAt': ts,
    });
    expect(await a.getDoc('join_codes/$token2'), isNotNull);
    print('3. участник создал код: OK');

    // 4) Вступление подтверждено — members-карточка B на месте.
    final member = await a.getDoc('family_spaces/$spaceId/members/$uidB');
    expect(member, isNotNull);
    print('4. вступление по токену: OK');

    // Cleanup: коды удаляет создатель.
    await a.signIn(emailA, pass);
    await a.deletePath('join_codes', token);
    await a.deletePath('join_codes', token2);
    await a.deletePath('family_spaces', spaceId);
    print('LEGACY INVITE: ALL OK');
  });
}
