import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_detail_screen.dart';
import 'package:agrobarter_app/screens/barter_screen.dart';

/// O PEDIDO DE FORA DO BARTER e o VALOR ALTERADO PELO ADMIN, do lado do app.
///
/// São as duas coisas que o consultor pede ao administrador sobre uma permuta
/// que já está montada: um item que a tabela da gestão não tem, e a correção de
/// um valor. O que estes testes protegem é o mesmo do pedido de alteração —
/// QUEM vê cada botão e QUEM vê a bandeira: oferecer o pedido a quem o servidor
/// recusaria é prometer um caminho que não existe, e esconder o pedido em
/// aberto de quem tem a permuta na mesa é deixá-lo trabalhar sobre uma lista de
/// insumos que está para crescer.
void main() {
  Map<String, dynamic> pedidoJson({
    int id = 1,
    String status = 'open',
    double? unitValue,
    double? sacksPerUnit,
    String? reply,
  }) => {
    'id': id,
    'productName': 'Semeadura por drone',
    'unit': 'ha',
    'quantity': 40,
    'note': 'O produtor quer a sobressemeadura de capim.',
    'status': status,
    'requestedBy': 'João Silva',
    'requestedAt': '2026-05-20T00:00:00.000Z',
    'unitValue': ?unitValue,
    'sacksPerUnit': ?sacksPerUnit,
    'reply': ?reply,
  };

  Map<String, dynamic> barterJson({
    String status = 'draft',
    int consultantId = 2,
    List<Map<String, dynamic>> productRequests = const [],
    String? changeRequestStatus,
    bool offBarterItem = false,
    double? listValue,
  }) => {
    'code': 'PRM-2026-009',
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
    'createdAt': '2026-05-14T00:00:00.000Z',
    if (changeRequestStatus != null) ...{
      'changeRequestStatus': changeRequestStatus,
      'changeRequestBy': 'João Silva',
      'changeRequestAt': '2026-05-21T00:00:00.000Z',
      'changeRequestFrom': status,
      'changeRequestNote': 'O valor da semente saiu diferente do combinado.',
    },
    'productRequests': productRequests,
    'items': [
      {
        'id': 10,
        'kind': 'grain',
        'productId': 1,
        'productName': 'Soja',
        'unit': 'saca 60kg',
        'quantity': 102.4646,
        'unitValue': 148.5,
      },
      {
        'id': 11,
        'kind': 'input',
        'productId': 5,
        'productName': 'NPK',
        'sku': 'NPK-0414',
        'unit': 'saco 50kg',
        'quantity': 60,
        'unitValue': 115.0,
        'listValue': listValue,
      },
      if (offBarterItem)
        {
          'id': 12,
          'kind': 'input',
          'productId': null,
          'productName': 'Semeadura por drone',
          'unit': 'ha',
          'quantity': 40,
          'unitValue': 250.0,
          'offBarter': true,
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

  group('a regra do pedido de produto', () {
    /// A janela vai do RASCUNHO até a mesa do comitê — e é aqui que ela difere
    /// do pedido de alteração, que começa onde esta termina: o consultor está
    /// montando a permuta e topa com o que falta.
    test('pede-se do rascunho até a mesa do comitê', () {
      for (final status in ['draft', 'sentToManager', 'pending']) {
        final barter = BarterModel.fromJson(barterJson(status: status));
        expect(barter.canRequestProductBy('2'), isTrue, reason: status);
      }
    });

    /// Depois da decisão, não: um insumo a mais mudaria o que o comitê
    /// aprovou. Dali em diante o caminho é o pedido de alteração.
    test('a permuta decidida não recebe mais pedido', () {
      for (final status in ['approved', 'approvedWithConditions', 'denied', 'invoiced']) {
        final barter = BarterModel.fromJson(barterJson(status: status));
        expect(barter.canRequestProductBy('2'), isFalse, reason: status);
      }
    });

    test('quem não registrou a permuta não pede produto para ela', () {
      final barter = BarterModel.fromJson(barterJson(consultantId: 3));
      expect(barter.canRequestProductBy('2'), isFalse);
      expect(barter.canRequestProductBy(null), isFalse);
    });

    test('o pedido em aberto acende a bandeira, e o decidido não', () {
      final aberto = BarterModel.fromJson(
        barterJson(productRequests: [pedidoJson()]),
      );
      expect(aberto.hasOpenProductRequest, isTrue);
      expect(aberto.openProductRequests, hasLength(1));

      final atendido = BarterModel.fromJson(
        barterJson(productRequests: [pedidoJson(status: 'added', unitValue: 250)]),
      );
      expect(atendido.hasOpenProductRequest, isFalse);
      expect(atendido.addedProductRequests, hasLength(1));
      expect(atendido.productRequests.first.total, 10000);
    });

    /// Quem pediu não vê R$: o valor chega a ele na moeda dele, convertido pelo
    /// servidor. O campo de R$ nem existe na resposta dele.
    test('o consultor lê o valor do pedido em sacas', () {
      final barter = BarterModel.fromJson(
        barterJson(productRequests: [pedidoJson(status: 'added', sacksPerUnit: 1.6835)]),
      );
      final pedido = barter.productRequests.first;
      expect(pedido.unitValue, isNull);
      expect(pedido.sacksPerUnit, closeTo(1.6835, 0.0001));
      // O total sai na mesma moeda: 40 ha × 1,6835 sc.
      expect(pedido.total, closeTo(67.34, 0.01));
    });

    /// O item incluído chega MARCADO, e sem produto no catálogo: é o que
    /// explica, no comprovante e no balcão, um valor que não está em tabela
    /// nenhuma.
    test('o item de fora do Barter vem marcado e sem produto', () {
      final barter = BarterModel.fromJson(barterJson(offBarterItem: true));
      final fora = barter.inputs.where((i) => i.offBarter).toList();

      expect(fora, hasLength(1));
      expect(fora.single.productId, isEmpty);
      expect(fora.single.total, 10000);
      // E o item de tabela continua sendo o que sempre foi.
      expect(barter.inputs.where((i) => !i.offBarter).single.productName, 'NPK');
    });

    /// O valor reescrito pelo admin guarda de onde saiu — sem isso, a tela
    /// mostraria um número sem história.
    test('o item corrigido diz qual era o valor de tabela', () {
      final barter = BarterModel.fromJson(barterJson(listValue: 120));
      final npk = barter.inputs.firstWhere((i) => i.productName == 'NPK');

      expect(npk.hasChangedValue, isTrue);
      expect(npk.listValue, 120);
      expect(npk.unitValue, 115);

      final semCorrecao = BarterModel.fromJson(barterJson());
      expect(semCorrecao.inputs.first.hasChangedValue, isFalse);
    });

    /// Sem nome, os atos novos apareceriam como "Andamento" — e a permuta cujo
    /// valor mudou não teria, na tela, nada explicando o quê.
    test('a linha do tempo nomeia os atos novos', () {
      String titulo(String action) => BarterEventModel.fromJson({
        'action': action,
        'toStatus': 'pending',
        'actorName': 'Carlos Mendes',
        'actorRole': 'admin',
        'at': '2026-05-21T00:00:00.000Z',
      }).title;

      expect(titulo('productRequested'), contains('fora do Barter'));
      expect(titulo('productAdded'), contains('incluído'));
      expect(titulo('productDenied'), contains('recusado'));
      expect(titulo('changeApplied'), contains('Valores alterados'));
    });
  });

  group('a tela do detalhe', () {
    Future<void> abrir(WidgetTester tester, BarterModel barter, {bool isAdmin = false}) async {
      tester.view.physicalSize = const Size(420, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: BarterDetailScreen(barter: barter, isAdmin: isAdmin)),
      );
      await tester.pump();
    }

    testWidgets('o consultor que registrou pede produto de fora', (tester) async {
      AppData.currentUser = usuario(capabilities: const {'barters.productRequest'});
      await abrir(tester, BarterModel.fromJson(barterJson(status: 'pending')));

      expect(find.text('Pedir Produto de Fora'), findsOneWidget);
    });

    testWidgets('na permuta já decidida o botão não existe', (tester) async {
      AppData.currentUser = usuario(capabilities: const {'barters.productRequest'});
      await abrir(tester, BarterModel.fromJson(barterJson(status: 'approved')));

      expect(find.text('Pedir Produto de Fora'), findsNothing);
    });

    /// A bandeira é de todo mundo que enxerga a permuta — as AÇÕES não.
    testWidgets('o gerente vê o pedido em aberto, e não as ações do admin', (tester) async {
      AppData.currentUser = usuario(
        id: '7',
        role: UserRole.manager,
        capabilities: const {'barters.opinion'},
      );
      await abrir(
        tester,
        BarterModel.fromJson(
          barterJson(status: 'sentToManager', productRequests: [pedidoJson()]),
        ),
      );

      expect(find.text('Pedidos de fora do Barter'), findsOneWidget);
      expect(find.text('Aguarda o administrador'), findsOneWidget);
      expect(find.text('Incluir'), findsNothing);
    });

    testWidgets('o admin atende ou recusa o pedido em aberto', (tester) async {
      AppData.currentUser = usuario(
        id: '1',
        role: UserRole.admin,
        capabilities: const {'barters.productReview', 'barters.readAll'},
      );
      await abrir(
        tester,
        BarterModel.fromJson(
          barterJson(status: 'sentToManager', productRequests: [pedidoJson()]),
        ),
        isAdmin: true,
      );

      expect(find.text('Incluir'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
    });

    /// A TERCEIRA saída do pedido de alteração: atender mexendo no valor, sem
    /// devolver a permuta ao rascunho. Ela é do mesmo dono da decisão.
    testWidgets('o admin pode alterar o valor sem devolver a permuta', (tester) async {
      AppData.currentUser = usuario(
        id: '1',
        role: UserRole.admin,
        capabilities: const {'barters.changeReview', 'barters.readAll'},
      );
      await abrir(
        tester,
        BarterModel.fromJson(barterJson(status: 'pending', changeRequestStatus: 'open')),
        isAdmin: true,
      );

      expect(find.text('Alterar valores sem devolver'), findsOneWidget);
      // As outras duas saídas continuam onde estavam.
      expect(find.text('Liberar'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
    });

    /// Quem não decide o pedido não altera valor nenhum — nem o consultor que
    /// pediu, nem o gerente que tem a permuta na mesa.
    testWidgets('o consultor não vê o botão de alterar valores', (tester) async {
      AppData.currentUser = usuario(capabilities: const {'barters.changeRequest'});
      await abrir(
        tester,
        BarterModel.fromJson(barterJson(status: 'pending', changeRequestStatus: 'open')),
      );

      expect(find.text('Alterar valores sem devolver'), findsNothing);
    });
  });

  /// A TELA QUE MONTA A PERMUTA — onde a falta de um item aparece de verdade.
  ///
  /// O pedido é amarrado a uma permuta, e o que existe aqui é uma SIMULAÇÃO:
  /// ela mora no aparelho, e o servidor não a conhece. A porta existe mesmo
  /// assim, e ela registra a permuta como rascunho antes de pedir — o que este
  /// teste protege é que ela esteja LÁ, no fim da lista de insumos, e que o
  /// aviso diga o que vai acontecer. Sem isso, o consultor que não achou o
  /// adjuvante precisaria descobrir sozinho que o caminho começa em outra tela.
  group('a tela da simulação', () {
    setUp(() {
      AppData.producers = [
        ProducerModel.fromJson({
          'id': 1,
          'name': 'Osmar Dutra',
          'consultantIds': [2],
          'document': '123.456.789-00',
          'farmName': 'Fazenda Boa Vista',
          'city': 'Campo Mourão/PR',
          'areaHa': 150,
          'createdAt': '2026-01-01T00:00:00.000Z',
        }),
      ];
      AppData.units = [
        UnitModel.fromJson({
          'id': 2,
          'name': 'Filial 02',
          'city': 'Sarandi/PR',
          'createdAt': '2026-01-01T00:00:00.000Z',
        }),
      ];
      AppData.inputs = [
        ProductModel.fromJson({
          'id': 5,
          'name': 'Fertilizante NPK 04-14-08',
          'unit': 'saco 50kg',
          'type': 'input',
          'currentPrice': 115.0,
          'requiredPerHa': 0,
        }),
      ];
      // O consultor não vê R$: a tabela chega a ele em SACAS por unidade, e é
      // por isso que o preço vem em `sacksPerUnit`.
      AppData.currentVersion = BarterVersionModel.fromJson({
        'id': 2,
        'code': 'S2026.02',
        'number': 2,
        'grainId': 1,
        'grainName': 'Soja',
        'grainUnit': 'saca 60kg',
        'status': 'active',
        'isOpen': true,
        'startsAt': '2026-01-01T00:00:00.000Z',
        'prices': [
          {
            'productId': 5,
            'productName': 'Fertilizante NPK 04-14-08',
            'unit': 'saco 50kg',
            'sacksPerUnit': 0.7744,
          },
        ],
      });
    });

    tearDown(() {
      AppData.producers = [];
      AppData.units = [];
      AppData.currentVersion = null;
    });

    testWidgets('a porta do pedido fica no fim da lista de insumos', (tester) async {
      final consultor = usuario(capabilities: const {'barters.productRequest'});
      AppData.currentUser = consultor;

      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: NewBarterScreen(consultant: consultor)));
      await tester.pumpAndSettle();

      // Etapa 1: o produtor da carteira. Etapa 2: onde ele retira.
      await tester.tap(find.text('Osmar Dutra'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filial 02'));
      await tester.pumpAndSettle();

      // Etapa 3: a lista de insumos — e, no fim dela, o que fazer quando o
      // insumo que o produtor quer não está ali.
      expect(find.text('Fertilizante NPK 04-14-08'), findsOneWidget);
      expect(find.text('Falta um insumo na lista?'), findsOneWidget);
      // O aviso é a parte que não pode faltar: o pedido REGISTRA a permuta, e
      // esta tela promete no rodapé que nada é enviado agora.
      expect(find.textContaining('registrada como rascunho'), findsOneWidget);
    });
  });
}
