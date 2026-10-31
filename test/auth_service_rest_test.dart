import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:planer/data/auth_service.dart';
import 'package:planer/data/storage.dart';

/// Тестовый бинд блокирует HTTP (все ответы 400) — возвращаем настоящий клиент.
class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  test('AuthService REST fallback: signIn/register + signOut', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();

    const email = 'planer-rest-test-2026@example.com';
    const password = 'restTest2026';

    final auth = AuthService.instance;
    await auth.init();
    print('init: isGuest=${auth.isGuest.value} userKey=${auth.userKey.value}');

    final r1 = await auth.signIn(email: email, password: password);
    print('signIn result: $r1');
    expect(r1, 'ok');
    expect(auth.isGuest.value, isFalse);
    expect(auth.userKey.value, isNotNull);
    expect(auth.userEmail.value, email);
    print('signed in as ${auth.userKey.value} (${auth.userEmail.value})');

    await auth.signOut();
    expect(auth.isGuest.value, isTrue);
    print('signOut OK, isGuest=${auth.isGuest.value}');

    final uniq = DateTime.now().millisecondsSinceEpoch;
    final r2 = await auth.register(
      email: 'planer-rest-reg-$uniq@example.com',
      password: password,
    );
    print('register result: $r2');
    expect(r2, 'ok');
    expect(auth.isGuest.value, isFalse);
    await auth.signOut();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
