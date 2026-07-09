import 'package:flutter_test/flutter_test.dart';
import 'package:barter_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BarterApp());
    expect(find.text('Bem-vindo'), findsOneWidget);
  });
}
