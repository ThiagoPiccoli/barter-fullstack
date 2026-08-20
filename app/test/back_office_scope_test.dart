import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/back_office_main_screen.dart';
import 'package:agrobarter_app/screens/barters_screen.dart';
import 'package:agrobarter_app/theme/app_theme.dart';

/// O QUE CADA POSTO DA RETAGUARDA ENXERGA — na tela, e não só na API.
///
/// O recorte de verdade é do servidor (`scopeFor`, em barters.service.ts). O que
/// estes testes seguram é a outra metade: a tela não pode DESENHAR o que está
/// fora do alcance de quem olha. O faturista abria abas "No gerente" e "No
/// comitê" e um painel que contava as permutas paradas nessas duas etapas —
/// portas para cômodos onde ele não entra, e números que ele não podia abrir,
/// conferir nem resolver.
void main() {
  UserModel staff(UserRole role, List<String> capabilities) => UserModel(
        id: '9',
        name: 'Patrícia Lemos',
        email: 'patricia@agrobarter.com.br',
        role: role,
        phone: '',
        branch: 'Matriz',
        unitId: '1',
        avatarInitials: 'PL',
        createdAt: DateTime(2024, 1, 1),
        capabilities: capabilities.toSet(),
      );

  /// Uma permuta parada em [status]. O que importa aqui é o estado — os itens
  /// existem só para a tela ter o que somar.
  ///
  /// [manager] e [waitingDays] só interessam ao painel do comitê, que agrupa o
  /// que está no gerente por PESSOA e ordena por tempo de espera.
  BarterModel barter(
    String code,
    String status, {
    String manager = 'Beatriz Nogueira',
    int waitingDays = 1,
  }) =>
      BarterModel.fromJson({
        'code': code,
        'consultantId': 2,
        'consultantName': 'João Silva',
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Antônio Carvalho',
        'unitId': 2,
        'unitName': 'Filial 02 – Gran. Santa T.',
        'status': status,
        'managerId': 7,
        'managerName': manager,
        'createdAt': DateTime.now()
            .subtract(Duration(days: waitingDays, hours: 1))
            .toUtc()
            .toIso8601String(),
        'items': [
          {
            'kind': 'grain',
            'productId': 1,
            'productName': 'Soja',
            'unit': 'saca 60kg',
            'quantity': 80.0,
            'unitValue': 148.5,
          },
          {
            'kind': 'input',
            'productId': 5,
            'productName': 'NPK',
            'unit': 'saco 50kg',
            'quantity': 48.0,
            'unitValue': 115.0,
          },
        ],
      });

  /// O cache com a linha INTEIRA dentro. É de propósito: mesmo que o aparelho
  /// tenha permutas de outras etapas (cache antigo, papel trocado), a tela do
  /// faturista não pode oferecê-las.
  void seedLinhaInteira() {
    AppData.barters = [
      barter('PRM-2026-001', 'invoiced'),
      barter('PRM-2026-002', 'pending'),
      barter('PRM-2026-003', 'denied'),
      barter('PRM-2026-004', 'approved'),
      barter('PRM-2026-005', 'sentToManager'),
    ];
  }

  tearDown(() {
    AppData.barters = [];
    AppData.currentUser = null;
  });

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: tela));
    await tester.pumpAndSettle();
  }

  group('abas da lista de permutas', () {
    testWidgets('o faturista só tem as etapas que chegaram nele', (tester) async {
      AppData.currentUser = staff(UserRole.biller, [
        Capability.bartersInvoice,
        Capability.bartersReadInvoicing,
        Capability.pricesRead,
      ]);
      seedLinhaInteira();

      await abrir(
        tester,
        const BartersScreen(isAdmin: true, consultantId: null),
      );

      // As abas trazem a contagem entre parênteses — é o que as distingue de um
      // selo de estado dentro de um cartão da lista.
      expect(find.textContaining('A faturar ('), findsOneWidget);
      expect(find.textContaining('Faturadas ('), findsOneWidget);
      // As etapas anteriores não são dele — nem como aba vazia.
      expect(find.textContaining('No gerente ('), findsNothing);
      expect(find.textContaining('No comitê ('), findsNothing);
      expect(find.textContaining('Negadas ('), findsNothing);
      // "Todas", com duas etapas, seria a soma das duas ao lado.
      expect(find.textContaining('Todas ('), findsNothing);
    });

    /// O COMITÊ é o oposto: ele decide, e para decidir precisa ver o que vem
    /// vindo — inclusive o que ainda está na mesa do gerente.
    testWidgets('o comitê acompanha a linha inteira, o gerente inclusive', (tester) async {
      AppData.currentUser = staff(UserRole.committee, [
        Capability.bartersReview,
        Capability.pricesRead,
      ]);
      seedLinhaInteira();

      await abrir(
        tester,
        const BartersScreen(isAdmin: true, consultantId: null),
      );

      for (final aba in ['Todas', 'No gerente', 'No comitê', 'A faturar', 'Faturadas', 'Negadas']) {
        expect(find.textContaining('$aba ('), findsOneWidget, reason: 'falta a aba "$aba"');
      }
    });
  });

  group('painel da retaguarda', () {
    /// A FAIXA DE NÚMEROS conta o que é de quem olha. Para o faturista: o que
    /// espera nota e o que ele já faturou — e nada das etapas de antes.
    testWidgets('o painel do faturista não conta etapa que ele não enxerga', (tester) async {
      final faturista = staff(UserRole.biller, [
        Capability.bartersInvoice,
        Capability.bartersReadInvoicing,
        Capability.pricesRead,
      ]);
      AppData.currentUser = faturista;
      // O cache do faturista É o que o servidor lhe manda: o que chegou ao
      // faturamento, e nada mais. Não há regra de escopo em Dart, e não deve
      // haver — a tela desenha o que veio.
      AppData.barters = [
        barter('PRM-2026-001', 'invoiced'),
        barter('PRM-2026-004', 'approved'),
      ];

      await abrir(tester, BackOfficeMainScreen(user: faturista));

      expect(find.text('Esperando você'), findsOneWidget);
      expect(find.text('Faturadas'), findsOneWidget);
      // As etapas de antes não aparecem nem como rótulo de um número zerado.
      expect(find.text('No comitê'), findsNothing);
      expect(find.text('No gerente'), findsNothing);
    });

    /// O comitê vê PARA TRÁS: o que está no gerente é a fila que vai cair na
    /// mesa dele.
    testWidgets('o painel do comitê mostra o que ainda está no gerente', (tester) async {
      final comite = staff(UserRole.committee, [
        Capability.bartersReview,
        Capability.pricesRead,
      ]);
      AppData.currentUser = comite;
      seedLinhaInteira();

      await abrir(tester, BackOfficeMainScreen(user: comite));

      expect(find.text('Esperando você'), findsOneWidget);
      // Uma vez na faixa de números; as outras são selos de estado na lista.
      expect(find.text('No gerente'), findsAtLeastNWidgets(1));
    });

    /// O PAINEL DO QUE VEM VINDO, que é o pedido por trás de "o comitê pode ver
    /// os que estão no gerente": não é só alcançar a etapa de trás, é conseguir
    /// LER a fila dela — quem está segurando, quanto, e há quanto tempo.
    testWidgets('o comitê lê o que está no gerente, por gerente e por espera', (tester) async {
      final comite = staff(UserRole.committee, [
        Capability.bartersReview,
        Capability.pricesRead,
      ]);
      AppData.currentUser = comite;
      AppData.barters = [
        barter('PRM-2026-007', 'sentToManager', manager: 'Gustavo Ramos', waitingDays: 2),
        barter('PRM-2026-005', 'sentToManager', waitingDays: 12),
        barter('PRM-2026-009', 'sentToManager', waitingDays: 3),
        barter('PRM-2026-002', 'pending'),
      ];

      await abrir(tester, BackOfficeMainScreen(user: comite));

      // Agrupado por pessoa: a Beatriz segura duas, o Gustavo uma.
      expect(find.text('Beatriz Nogueira'), findsOneWidget);
      expect(find.text('Gustavo Ramos'), findsOneWidget);
      expect(find.textContaining('2 permutas'), findsOneWidget);
      expect(find.textContaining('1 permuta •'), findsOneWidget);

      // O tempo da MAIS ANTIGA de cada um — é o número que faz alguém ligar.
      expect(find.text('há 12 dias'), findsOneWidget);
      expect(find.text('há 2 dias'), findsOneWidget);

      // E quem segura há mais tempo vem primeiro: em ordem alfabética, a linha
      // que se quer ler ficaria escondida no meio.
      expect(
        tester.getTopLeft(find.text('Beatriz Nogueira')).dy,
        lessThan(tester.getTopLeft(find.text('Gustavo Ramos')).dy),
      );
    });

    /// Vazio, o painel FICA — pelo mesmo motivo do cartão de fila vazia: um
    /// bloco que some deixa quem olha sem saber se não há nada vindo ou se o
    /// app não carregou.
    testWidgets('sem nada no gerente, o painel do comitê diz isso', (tester) async {
      final comite = staff(UserRole.committee, [Capability.bartersReview]);
      AppData.currentUser = comite;
      AppData.barters = [barter('PRM-2026-002', 'pending')];

      await abrir(tester, BackOfficeMainScreen(user: comite));

      expect(find.text('Nenhuma permuta esperando parecer agora.'), findsOneWidget);
    });

    /// O ROADMAP SAIU DA TELA. "Acesso de Faturista liberado — por enquanto o
    /// acompanhamento é em modo leitura. Em construção: …" era o app explicando
    /// a si mesmo para quem trabalha nele todo dia, e ocupava a tela inteira
    /// entre a fila e as permutas.
    testWidgets('nenhum papel recebe cartão de "em construção"', (tester) async {
      for (final papel in [
        staff(UserRole.biller, [Capability.bartersInvoice, Capability.bartersReadInvoicing]),
        staff(UserRole.committee, [Capability.bartersReview]),
        staff(UserRole.manager, [Capability.bartersOpinion, Capability.bartersReadTeam]),
      ]) {
        AppData.currentUser = papel;
        seedLinhaInteira();

        await abrir(tester, BackOfficeMainScreen(user: papel));

        expect(find.textContaining('Em construção'), findsNothing);
        expect(find.textContaining('modo leitura'), findsNothing);
        expect(find.textContaining('Acesso de'), findsNothing);
        expect(find.textContaining('Ainda vem por aí'), findsNothing);
      }
    });
  });
}
