import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:planer/data/auth_service.dart';
import 'package:planer/data/family_service.dart';
import 'package:planer/data/storage.dart';

/// Сквозное вступление по коду: копирование многострочного текста → вставка.
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
    SharedPreferences.setMockInitialValues({});
  });

  test('joinByCode: владелец генерирует ссылку, второй вступает по ней',
      () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    final auth = AuthService.instance;
    await auth.init();

    // Владелец — аккаунт A.
    final r = await auth.signIn(
      email: 'planer-rest-test-2026@example.com',
      password: 'restTest2026',
    );
    expect(r, 'ok');

    final fam = FamilyService.instance;
    await fam.load();
    final space = await fam.createSpace(name: 'Ссылка-тест');
    print('создано пространство ${space.id}');

    final token = await fam.generateJoinCode(space.id);
    print('токен: $token');

    // Формируем тот же текст, что копирует кнопка «Пригласить по ссылке».
    final copied = 'Приглашение в «${space.name}» (Планер)\n'
        'planer://join/$token\n'
        'Код: $token';
    print('скопировано: $copied');
    await auth.signOut();

    // Второй пользователь вставляет весь текст целиком.
    final r2 = await auth.signIn(
      email: 'planer-rest-test2-2026@example.com',
      password: 'restTest2026',
    );
    expect(r2, 'ok');
    await fam.load();
    final name = await fam.joinByCode(copied);
    print('вступили в: $name');
    expect(name, 'Ссылка-тест');

    // Пространство должно появиться у второго пользователя.
    await fam.load();
    expect(fam.spaces.value.any((s) => s.name == 'Ссылка-тест'), isTrue,
        reason: 'пространство должно быть в списке после вступления');
    await auth.signOut();

    // Владелец убирает за собой.
    await auth.signIn(
      email: 'planer-rest-test-2026@example.com',
      password: 'restTest2026',
    );
    await fam.load();
    await fam.deleteSpace(space.id);
    await auth.signOut();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
