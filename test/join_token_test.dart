import 'package:flutter_test/flutter_test.dart';
import 'package:planer/data/family_service.dart';

void main() {
  test('extractJoinToken: все форматы вставки', () {
    const token = 'plntest_hnq5ig65xe';

    // Голый токен.
    expect(FamilyService.extractJoinToken(token), token);

    // Ссылка приложения.
    expect(FamilyService.extractJoinToken('planer://join/$token'), token);

    // Ссылка с завершающим слэшем.
    expect(FamilyService.extractJoinToken('planer://join/$token/'), token);

    // Полный текст, который копируется в буфер (многострочный!).
    final fullText = 'Приглашение в «Семья» (Планер)\n'
        'planer://join/$token\n'
        'Код: $token';
    expect(FamilyService.extractJoinToken(fullText), token,
        reason: 'многострочное сообщение должно разбираться');

    // Токен в начале строки с мусором вокруг.
    expect(FamilyService.extractJoinToken('код: $token спасибо'), token);

    // https-форма.
    expect(FamilyService.extractJoinToken('https://x.y/#$token'), token);

    // Токен со знаком минус (такое бывало при переполнении генератора).
    const oldToken = 'plnhnq7umy0pw_-i7kgo3g';
    expect(FamilyService.extractJoinToken('planer://join/$oldToken'), oldToken,
        reason: 'токен с минусом должен распознаваться целиком');
    expect(FamilyService.extractJoinToken(oldToken), oldToken);
  });

  test('extractJoinToken: пустой и мусор', () {
    expect(FamilyService.extractJoinToken(''), isEmpty);
    expect(FamilyService.extractJoinToken('   '), isEmpty);
  });
}
