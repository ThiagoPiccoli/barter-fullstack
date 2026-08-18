import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agrobarter_app/data/demo_seed.dart';
import 'package:agrobarter_app/main.dart' as app;
import 'package:agrobarter_app/services/token_storage.dart';

/// Tour de ponta a ponta contra a API REAL (exige o servidor no ar com o
/// seed fresco: `cd api && npm run db:reset && npm run start:dev`):
/// 1. Carteira de produtores: cada consultor só vê na Nova Permuta os que
///    atende — inclusive o produtor COMPARTILHADO, que está na carteira de
///    dois; o admin vê todos nos Cadastros, com a carteira de cada um.
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
    // Login real: a senha é obrigatória (todos os usuários do seed).
    await tester.enterText(find.byType(TextField).at(1), demoSeedPassword);
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

  testWidgets('carteira por consultor + PDF na finalização', (tester) async {
    // O app agora retoma a sessão guardada no aparelho; o tour começa do zero,
    // senão a sessão deixada por uma execução anterior pularia o login.
    await TokenStorage.clear();
    app.main();
    await tester.pumpAndSettle();

    // ── João (u002) só vê a própria carteira na Nova Permuta ──────────────
    await login(tester, 'joao.silva@agrobarter.com.br');
    await goToTab(tester, 'Nova Permuta');
    expect(find.text('Antônio Carvalho'), findsOneWidget);
    expect(find.text('Sebastião Ramos'), findsOneWidget);
    // Joaquim Tavares é atendido pelo João E pelo Roberto — região dividida.
    // Ele aparece aqui e também na carteira do Roberto, e é o mesmo cadastro.
    expect(find.text('Joaquim Tavares'), findsOneWidget);
    expect(find.text('Helena Prado'), findsNothing);
    expect(find.text('Osmar Dutra'), findsNothing);
    expect(find.text('Vanessa Lopes'), findsNothing);
    await shot('01-joao-carteira');
    await logout(tester);

    // ── Admin vê todos os produtores, com o dono de cada carteira ──────────
    await login(tester, 'admin@agrobarter.com.br');
    await goToTab(tester, 'Cadastros');
    expect(find.textContaining('Carteira:'), findsWidgets);
    await scrollTo(tester, find.text('Osmar Dutra'));
    expect(find.text('Osmar Dutra'), findsOneWidget);
    await shot('02-admin-cadastros');

    // Perfil do consultor mostra a carteira dele.
    await tester.tap(find.text('Consultores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('João Silva'));
    await tester.pumpAndSettle();
    // Três: os dois só dele mais o compartilhado com o Roberto.
    await scrollTo(tester, find.text('Carteira de Produtores (3)'));
    await scrollTo(tester, find.text('Antônio Carvalho'));
    expect(find.text('Sebastião Ramos'), findsOneWidget);
    expect(find.text('Joaquim Tavares'), findsOneWidget);
    await shot('03-admin-perfil-consultor-carteira');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await logout(tester);

    // ── Ana (u003) vê outra carteira e finaliza uma permuta com PDF ────────
    await login(tester, 'ana.ferreira@agrobarter.com.br');
    await goToTab(tester, 'Nova Permuta');
    expect(find.text('Helena Prado'), findsOneWidget);
    expect(find.text('Cláudia Nunes'), findsOneWidget);
    expect(find.text('Antônio Carvalho'), findsNothing);
    await shot('04-ana-carteira');

    await tester.tap(find.text('Helena Prado'));
    await tester.pumpAndSettle();
    // Não existe mais etapa de grão: o Barter vigente já diz em que grão se
    // paga, e a faixa no topo mostra qual versão está valendo.
    expect(find.textContaining('Pagamento em'), findsOneWidget);

    // Etapa 2: a unidade de retirada. Qualquer uma serve — ela é logística e
    // não muda de quem é o parecer.
    expect(find.textContaining('Etapa 2'), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await shot('05-ana-insumos');

    // O construtor tem UM desfecho: guardar a simulação, sem tocar na rede.
    // Encaminhar ao gerente é ato próprio, na aba de simulações.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar simulação'));
    await tester.pumpAndSettle();

    await goToTab(tester, 'Permutas');
    await tester.tap(find.textContaining('Simulações'));
    await tester.pumpAndSettle();
    expect(find.text('Helena Prado'), findsOneWidget);
    expect(find.text('Não enviada'), findsOneWidget);
    await shot('06-ana-simulacao-guardada');

    // Encaminhar: confere serviço e valores, mostra o resumo, e só então grava.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Encaminhar'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Encaminhar ao gerente?'), findsOneWidget);
    await shot('07-ana-resumo-do-envio');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Encaminhar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Permuta Enviada!'), findsOneWidget);
    expect(find.text('Gerar PDF'), findsOneWidget);
    await shot('08-permuta-enviada-com-pdf');

    // Gera o PDF: abre a folha de compartilhamento nativa do iOS. O marcador
    // avisa o host para capturar a tela inteira via simctl (a folha é nativa,
    // fora da árvore Flutter).
    await tester.tap(find.text('Gerar PDF'));
    debugPrint('PDF_SHARE_OPEN');
    await Future<void>.delayed(const Duration(seconds: 25));
  });
}
