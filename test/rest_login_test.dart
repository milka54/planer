import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/firebase_rest.dart';

void main() {
  test('REST fallback: register/signIn/refresh/signOut', () async {
    final rest = FirebaseRest.instance;
    const email = 'planer-rest-test-2026@example.com';
    const password = 'restTest2026';

    // 1) signIn (или register, если аккаунта нет)
    try {
      final data = await rest.signIn(email, password);
      print('signIn OK: uid=${data['localId']} email=${data['email']}');
    } on RestAuthException catch (e) {
      print('signIn failed (${e.message}) — trying register');
      final data = await rest.register(email, password);
      print('register OK: uid=${data['localId']}');
    }
    expect(rest.isSignedIn, isTrue);
    expect(rest.uid, isNotNull);
    expect(rest.idToken, isNotNull);
    print('uid=${rest.uid} email=${rest.email}');

    // 2) refresh session
    final oldToken = rest.idToken;
    rest.idToken = null; // форсируем обновление
    await rest.refreshSession();
    expect(rest.idToken, isNotNull);
    print('refresh OK: newToken=${rest.idToken != oldToken}');

    // 3) signOut
    await rest.signOut();
    expect(rest.isSignedIn, isFalse);
    print('signOut OK');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
