import 'package:flutter_test/flutter_test.dart';
import 'package:planer/main.dart';

void main() {
  testWidgets('Планер smoke', (tester) async {
    await tester.pumpWidget(const PlanerApp());
    expect(find.byType(PlanerApp), findsOneWidget);
  });
}
