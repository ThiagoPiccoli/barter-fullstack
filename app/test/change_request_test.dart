import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_detail_screen.dart';

/// O PEDIDO DE ALTERAÇÃO, do lado do app.
///
/// Ele é o único caminho de volta da esteira, e custa caro quando é atendido: a
/// permuta volta a rascunho e o parecer do gerente e a decisão do comitê são
/// refeitos. O que estes testes protegem é QUEM vê o botão e QUEM vê a bandeira
/// — oferecer o pedido a quem o servidor recusaria (403/422) é prometer um
/// caminho que não existe, e esconder a bandeira de quem tem a permuta na mesa
/// é deixá-lo gastar um parecer sobre insumos que estão prestes a mudar.
void main() {
  Map<String, dynamic> barterJson({
    String status = 'approved',
    int consultantId = 2,
    String? changeRequestStatus,
    String? changeRequestNote,
    String? changeRequestReply,
  }) => {
    'code': 'PRM-2026-001',
    'versionCode': 'S2026.02',
    'consultantId': consultantId,
    'consultantName': 'João Silva',
    'consultantBranch': 'Filial 02',
    'producerId': 1,
    'producerName': 'Antônio Carvalho',
    'unitId': 2,
    'unitName': 'Filial 02',
    'status': status,
    'managerId': 7,
    'managerName': 'Beatriz Nogueira',
    'createdAt': '2026-01-10T00:00:00.000Z',
    if (changeRequestStatus != null) ...{
      'changeRequestStatus': changeRequestStatus,
      'changeRequestBy': 'João Silva',
      'changeRequestAt': '2026-03-01T00:00:00.000Z',
      'changeRequestFrom': status,
      'changeRequestNote': changeRequestNote ?? 'O produtor trocou o fungicida na véspera.',
      'changeRequestReply': ?changeRequestReply,
    },
    'items': [
      {
        'kind': 'grain',
        'productId': 1,
        'productName': 'Soja',
        'unit': 'saca 60kg',
        'quantity': 80.4444,
        'unitValue': 148.5,
      },
      {
        'kind': 'input',
        'productId': 5,
        'productName': 'NPK',
        'sku': 'NPK-0414',
        'unit': 'saco 50kg',
        'quantity': 48,
        'unitValue': 115.0,
      },
    ],
  };

  UserModel usuario({
    String id = '2',
    UserRole role = UserRole.consultant,
    required Set<String> capabilities,
  }) => UserModel(
    id: id,
    name: 'João Silva',
    email: 'joao@coop.test',
    phone: '',
    branch: 'Filial 02',
    role: role,
    avatarInitials: 'JS',
    createdAt: DateTime(2026, 1, 1),
    capabilities: capabilities,
  );

  tearDown(() {
    AppData.currentUser = null;
    AppData.inputs = [];
    AppData.grains = [];
  });

  group('a regra do pedido', () {
    /// O consultor que registrou pede em tudo que já saiu da mão dele — a
    /// negada inclusive, que é a permuta que mais precisa ser refeita.
    test('pede-se em qualquer permuta que já saiu da mão do consultor', () {
      for (final status in ['sentToManager', 'pending', 'approved', 'denied']) {
        final barter = BarterModel.fromJson(barterJson(status: status));
        expect(barter.canBeChangedBy('2'), isTrue, reason: status);
      }
    });

    /// O rascunho já é dele — altera-se direto; a faturada saiu para fora, e o
    /// que saiu não se corrige por aqui.
    test('o rascunho e a faturada ficam de fora', () {
      expect(BarterModel.fromJson(barterJson(status: 'draft')).canBeChangedBy('2'), isFalse);
      expect(BarterModel.fromJson(barterJson(status: 'invoiced')).canBeChangedBy('2'), isFalse);
    });

    test('quem não registrou a permuta não pede alteração dela', () {
      final barter = BarterModel.fromJson(barterJson(consultantId: 3));
      expect(barter.canBeChangedBy('2'), isFalse);
      expect(barter.canBeChangedBy(null), isFalse);
    });

    /// Um pedido por vez: dois em aberto dariam ao admin duas versões do que
    /// precisa mudar, e decidir uma apagaria a outra.
    test('com um pedido em aberto não se pede de novo', () {
      final barter = BarterModel.fromJson(barterJson(changeRequestStatus: 'open'));
      expect(barter.hasOpenChangeRequest, isTrue);
      expect(barter.canBeChangedBy('2'), isFalse);
    });

    /// Recusado, pede-se outra vez: o motivo da recusa pode ter sido resolvido.
    test('depois de recusado, pede-se outra vez — e o motivo continua visível', () {
      final barter = BarterModel.fromJson(
        barterJson(changeRequestStatus: 'denied', changeRequestReply: 'A retirada já foi separada.'),
      );
      expect(barter.changeRequestDenied, isTrue);
      expect(barter.changeRequestReply, contains('separada'));
      expect(barter.canBeChangedBy('2'), isTrue);
    });

    /// Os três atos do desvio contam a história na linha do tempo. Sem nome,
    /// eles apareceriam como "Andamento" — e a permuta que voltou a rascunho
    /// não teria, na tela, nada explicando por quê.
    test('a linha do tempo nomeia os três atos do desvio', () {
      String titulo(String action) => BarterEventModel.fromJson({
        'action': action,
        'toStatus': 'approved',
        'actorName': 'Carlos Mendes',
        'actorRole': 'admin',
        'at': '2026-03-01T00:00:00.000Z',
      }).title;

      expect(titulo('changeRequested'), 'Alteração solicitada');
      expect(titulo('changeAccepted'), contains('rascunho'));
      expect(titulo('changeDenied'), contains('recusado'));
    });
  });

  group('a tela do detalhe', () {
    Future<void> abrir(WidgetTester tester, BarterModel barter, {bool isAdmin = false}) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: BarterDetailScreen(barter: barter, isAdmin: isAdmin)),
      );
      await tester.pump();
    }

    testWidgets('o consultor que registrou vê o pedido de alteração', (tester) async {
      AppData.currentUser = usuario(capabilities: const {'barters.changeRequest'});
      await abrir(tester, BarterModel.fromJson(barterJson()));

      expect(find.text('Solicitar Alteração'), findsOneWidget);
    });

    testWidgets('na permuta faturada o botão não existe', (tester) async {
      AppData.currentUser = usuario(capabilities: const {'barters.changeRequest'});
      await abrir(tester, BarterModel.fromJson(barterJson(status: 'invoiced')));

      expect(find.text('Solicitar Alteração'), findsNothing);
    });

    /// A BANDEIRA é de todo mundo que enxerga a permuta: quem a tem na mesa
    /// precisa saber que os insumos podem mudar antes de trabalhar nela.
    testWidgets('o gerente vê a bandeira, e não as ações do admin', (tester) async {
      AppData.currentUser = usuario(
        id: '7',
        role: UserRole.manager,
        capabilities: const {'barters.opinion'},
      );
      await abrir(
        tester,
        BarterModel.fromJson(barterJson(status: 'sentToManager', changeRequestStatus: 'open')),
      );

      expect(find.text('Alteração solicitada'), findsOneWidget);
      expect(find.text('Liberar'), findsNothing);
      expect(find.text('Recusar'), findsNothing);
    });

    testWidgets('o admin decide o pedido em aberto', (tester) async {
      AppData.currentUser = usuario(
        id: '1',
        role: UserRole.admin,
        capabilities: const {'barters.changeReview', 'barters.readAll'},
      );
      await abrir(tester, BarterModel.fromJson(barterJson(changeRequestStatus: 'open')),
          isAdmin: true);

      expect(find.text('Alteração solicitada'), findsOneWidget);
      expect(find.text('Liberar'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
      // Ele decide o PROCESSO, e continua sem decidir o negócio: aprovar e negar
      // permuta são do comitê, e não aparecem para ele.
      expect(find.text('Aprovar'), findsNothing);
    });

    /// O CÓDIGO do produto aparece junto do nome em cada item — é por ele que o
    /// insumo é achado no depósito e batido contra a nota.
    testWidgets('cada item mostra o código do produto', (tester) async {
      AppData.currentUser = usuario(capabilities: const {});
      await abrir(tester, BarterModel.fromJson(barterJson()));

      expect(find.text('NPK-0414'), findsOneWidget);
      expect(find.text('NPK'), findsOneWidget);
    });
  });
}
