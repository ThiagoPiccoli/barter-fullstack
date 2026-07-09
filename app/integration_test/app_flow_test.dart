import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:barter_app/main.dart' as app;

/// Tour completo pelas duas regras novas:
/// 1. Carteira de produtores: cada vendedor só vê os próprios produtores na
///    Nova Permuta; o admin vê todos nos Cadastros (com o dono da carteira).
/// 2. PDF de controle ao finalizar a permuta (e no detalhe de qualquer uma).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> login(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).first, email);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Entrar'));
    // _login simula 800ms de rede com um spinner que nunca "assenta".
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
    await binding.takeScreenshot('01-joao-carteira');
    await logout(tester);

    // ── Admin vê todos os produtores, com o dono de cada carteira ──────────
    await login(tester, 'admin@barter.com.br');
    await goToTab(tester, 'Cadastros');
    expect(find.textContaining('Carteira:'), findsWidgets);
    await scrollTo(tester, find.text('Osmar Dutra'));
    expect(find.text('Osmar Dutra'), findsOneWidget);
    await binding.takeScreenshot('02-admin-cadastros');

    // Perfil do vendedor mostra a carteira dele.
    await tester.tap(find.text('Vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('João Silva'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Carteira de Produtores (2)'));
    await scrollTo(tester, find.text('Antônio Carvalho'));
    expect(find.text('Sebastião Ramos'), findsOneWidget);
    await binding.takeScreenshot('03-admin-perfil-vendedor-carteira');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await logout(tester);

    // ── Ana (u003) vê outra carteira e finaliza uma permuta com PDF ────────
    await login(tester, 'ana.ferreira@barter.com.br');
    await goToTab(tester, 'Nova Permuta');
    expect(find.text('Helena Prado'), findsOneWidget);
    expect(find.text('Cláudia Nunes'), findsOneWidget);
    expect(find.text('Antônio Carvalho'), findsNothing);
    await binding.takeScreenshot('04-ana-carteira');

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
    await binding.takeScreenshot('05-permuta-enviada-com-pdf');

    // Gera o PDF: abre a folha de compartilhamento nativa do iOS. O marcador
    // avisa o host para capturar a tela inteira via simctl (a folha é nativa,
    // fora da árvore Flutter).
    await tester.tap(find.text('Gerar PDF'));
    debugPrint('PDF_SHARE_OPEN');
    await Future<void>.delayed(const Duration(seconds: 25));
  });
}
