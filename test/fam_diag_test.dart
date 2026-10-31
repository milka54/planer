import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';
import 'package:planer/data/models/family_space.dart';

void main() {
  test('Diagnose family_spaces paths', () async {
    final rest = FirebaseRest.instance;
    await rest.signIn('planer-rest-test-2026@example.com', 'restTest2026');
    final uid = rest.uid!;

    final space = FamilySpace.create(name: 'Диагностика', createdBy: uid);
    await rest.upsertPath('family_spaces', space.id, space.toFirestore());
    print('1. space doc written');

    final owner = FamilyMember(uid: uid, email: rest.email!, displayName: 't', role: 'owner', joinedAt: DateTime.now());
    try {
      await rest.pushSpaceDoc(space.id, 'members', uid, owner.toFirestore());
      print('2. member doc written');
    } catch (e) {
      print('2. member write FAIL: $e');
    }

    try {
      final m = await rest.getDoc('family_spaces/${space.id}/members/$uid');
      print('3. get member doc: ${m == null ? "NULL" : "OK ${m['role']}"}');
    } catch (e) {
      print('3. get member FAIL: $e');
    }

    try {
      final list = await rest.pullSpaceCollection(space.id, 'members');
      print('4. list members: ${list.length}');
    } catch (e) {
      print('4. list members FAIL: $e');
    }

    try {
      final list = await rest.fetchPath('family_spaces/${space.id}/members');
      print('5. fetchPath members: ${list.length}');
    } catch (e) {
      print('5. fetchPath members FAIL: $e');
    }

    // cleanup
    try { await rest.removeSpaceDoc(space.id, 'members', uid); } catch (_) {}
    try { await rest.deletePath('family_spaces', space.id); } catch (_) {}
    await rest.signOut();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
