import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/main.dart';

void main() {
  setUp(() {
    // Cofre em memória: o canal nativo não responde dentro de um teste de
    // widget e a tela de abertura ficaria esperando para sempre.
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  testWidgets('abre no login quando não há sessão guardada', (WidgetTester tester) async {
    await tester.pumpWidget(const BarterApp());

    // Sem token guardado, a abertura manda direto para o login. pumpAndSettle
    // não serve: o indicador de progresso da abertura anima sem parar.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Bem-vindo'), findsOneWidget);
  });

  testWidgets('servidor fora do ar não descarta a sessão guardada', (WidgetTester tester) async {
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({'barter.access_token': 'token-de-uma-sessão'});

    await tester.pumpWidget(const BarterApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // O binding de teste recusa qualquer requisição: isso é falha de
    // comunicação, não sessão inválida. O app oferece nova tentativa em vez de
    // derrubar quem já estava logado.
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Bem-vindo'), findsNothing);
  });
}
