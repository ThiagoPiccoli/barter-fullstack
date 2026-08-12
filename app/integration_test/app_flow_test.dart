import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:barter_app/main.dart' as app;
import 'package:barter_app/services/token_storage.dart';

/// Tour de ponta a ponta contra a API REAL (exige o servidor no ar com o
/// seed fresco: `cd api && npm run db:reset && npm run start:dev`):
/// 1. Carteira de produtores: cada vendedor só vê os próprios produtores na
///    Nova Permuta; o admin vê todos nos Cadastros (com o dono da carteira).
/// 2. Permuta criada de verdade no servidor + PDF de controle na finalização.
///
/// Atenção: o teste grava a permuta PRM-2026-009 no banco de desenvolvimento;
/// rode o db:reset novamente para zerar.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Screenshot best-effort: funciona via `flutter drive` (iOS/Android, com o
  /// test_driver salvando em build/verify_screenshots/); em desktop o canal
  /// não existe e o passo é simplesmente ignorado.
  Future<void> shot(String name) async {
    try {
      await binding.takeScreenshot(name);
    } catch (_) {}
  }

  Future<void> login(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).first, email);
    // Login real: a senha é obrigatória (todos os usuários do seed: 123456).
    await tester.enterText(find.byType(TextField).at(1), '123456');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Entrar'));
    // Aguarda a autenticação + carga inicial de dados da API.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  }

  Future<void> logout(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.logout).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sair'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo'), findsOneWidget);
  }

  Future<void> goToTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    ));
    await tester.pumpAndSettle();
  }

  // Rola a lista visível até o alvo aparecer. Mira o Scrollable do ListView:
  // campos de texto também são Scrollables e vêm antes na árvore.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    final list = find
        .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
        .hitTestable()
        .first;
    await tester.scrollUntilVisible(target, 300, scrollable: list);
    await tester.pumpAndSettle();
  }

  testWidgets('carteira por vendedor + PDF na finalização', (tester) async {
    // O app agora retoma a sessão guardada no aparelho; o tour começa do zero,
    // senão a sessão deixada por uma execução anterior pularia o login.
    await TokenStorage.clear();
    app.main();
    await tester.pumpAndSettle();

    // ── João (u002) só vê a própria carteira na Nova Permuta ──────────────
    await login(tester, 'joao.silva@barter.com.br');
    await goToTab(tester, 'Nova Permuta');
    expect(find.text('Antônio Carvalho'), findsOneWidget);
    expect(find.text('Sebastião Ramos'), findsOneWidget);
    expect(find.text('Helena Prado'), findsNothing);
    expect(find.text('Osmar Dutra'), findsNothing);
    expect(find.text('Vanessa Lopes'), findsNothing);
    await shot('01-joao-carteira');
    await logout(tester);

    // ── Admin vê todos os produtores, com o dono de cada carteira ──────────
    await login(tester, 'admin@barter.com.br');
    await goToTab(tester, 'Cadastros');
    expect(find.textContaining('Carteira:'), findsWidgets);
    await scrollTo(tester, find.text('Osmar Dutra'));
    expect(find.text('Osmar Dutra'), findsOneWidget);
    await shot('02-admin-cadastros');

    // Perfil do vendedor mostra a carteira dele.
    await tester.tap(find.text('Vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('João Silva'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Carteira de Produtores (2)'));
    await scrollTo(tester, find.text('Antônio Carvalho'));
    expect(find.text('Sebastião Ramos'), findsOneWidget);
    await shot('03-admin-perfil-vendedor-carteira');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await logout(tester);

    // ── Ana (u003) vê outra carteira e finaliza uma permuta com PDF ────────
    await login(tester, 'ana.ferreira@barter.com.br');
    await goToTab(tester, 'Nova Permuta');
    expect(find.text('Helena Prado'), findsOneWidget);
    expect(find.text('Cláudia Nunes'), findsOneWidget);
    expect(find.text('Antônio Carvalho'), findsNothing);
    await shot('04-ana-carteira');

    await tester.tap(find.text('Helena Prado'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pagar com Grãos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soja'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Enviar Permuta'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar Permuta'), findsOneWidget);
    await tester.tap(find.text('Confirmar e Enviar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Permuta Enviada!'), findsOneWidget);
    expect(find.text('Gerar PDF'), findsOneWidget);
    await shot('05-permuta-enviada-com-pdf');

    // Gera o PDF: abre a folha de compartilhamento nativa do iOS. O marcador
    // avisa o host para capturar a tela inteira via simctl (a folha é nativa,
    // fora da árvore Flutter).
    await tester.tap(find.text('Gerar PDF'));
    debugPrint('PDF_SHARE_OPEN');
    await Future<void>.delayed(const Duration(seconds: 25));
  });
}
