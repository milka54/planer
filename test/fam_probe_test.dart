import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';

void main() {
  test('Probe family_spaces create', () async {
    final r = FirebaseRest.instance;
    await r.signIn('planer-rest-test-2026@example.com', 'restTest2026');
    print('uid=${r.uid}');
    try {
      await r.upsertPath('family_spaces', 'probe_sec_1', {
        'id': 'probe_sec_1',
        'name': 'Probe',
        'createdBy': r.uid,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      print('CREATE space: OK');
    } catch (e) {
      print('CREATE space: FAIL $e');
    }
    try {
      final d = await r.getDoc('family_spaces/probe_sec_1');
      print('READ space: ${d == null ? "NULL" : "OK"}');
    } catch (e) {
      print('READ space: FAIL $e');
    }
    try {
      await r.deletePath('family_spaces', 'probe_sec_1');
      print('DELETE space: OK');
    } catch (e) {
      print('DELETE space: FAIL $e');
    }
    await r.signOut();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
