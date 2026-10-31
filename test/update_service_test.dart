import 'package:flutter_test/flutter_test.dart';
import 'package:planer/core/update_service.dart';

void main() {
  test('isNewer: сравнение версий', () {
    expect(UpdateService.isNewer('1.3.0', '1.2.0'), isTrue);
    expect(UpdateService.isNewer('1.2.0', '1.2.0'), isFalse);
    expect(UpdateService.isNewer('1.1.9', '1.2.0'), isFalse);
    expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
    expect(UpdateService.isNewer('1.2.1', '1.2.0'), isTrue);
    expect(UpdateService.isNewer('1.2.0', '1.2.1'), isFalse);
    // Неполные строки.
    expect(UpdateService.isNewer('1.3', '1.2.9'), isTrue);
    expect(UpdateService.isNewer('', '1.0.0'), isFalse);
  });

  test('appVersion соответствует формату X.Y.Z', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(UpdateService.appVersion), isTrue);
  });
}
