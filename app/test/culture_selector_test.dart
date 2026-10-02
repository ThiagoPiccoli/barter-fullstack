import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/barter_simulation.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_screen.dart';

/// A ESCOLHA DA CULTURA, na tela de verdade.
///
/// Cada cultura aberta é um Barter à parte — a Soja 26/27 e o Milho 2027, cada
/// um com a sua tabela, a sua cotação e o seu seguro —, e quem decide em qual
/// delas o cliente paga é o consultor, junto com o produtor. A escolha é a
/// PRIMEIRA etapa da permuta nova: ela decide quais insumos existem na lista.
///
/// O que estes testes guardam: a escolha existe quando há o que escolher, some
/// quando não há, e a simulação guardada volta na cultura em que foi montada.
void main() {
  UserModel consultor() => UserModel(
    id: '2',
    name: 'João Silva',
    email: 'joao@coop.test',
    phone: '',
    branch: 'Filial 02',
    role: UserRole.consultant,
    managerId: '7',
    managerName: 'Beatriz Nogueira',
    avatarInitials: 'JS',
    createdAt: DateTime(2026, 1, 1),
  );

  ProducerModel produtor() => ProducerModel(
    id: '10',
    name: 'Antônio Carvalho',
    consultantId: '2',
    document: '123.456.789-09',
    phone: '',
    farmName: 'Fazenda Boa Vista',
    city: 'Mandaguari/PR',
    avatarInitials: 'AC',
    createdAt: DateTime(2020, 1, 1),
  );

  BarterSimulation simulacao({String seasonId = '3', String grainId = '1'}) => BarterSimulation(
    id: 'sim-1',
    consultantId: '2',
    producerId: '10',
    producerName: 'Antônio Carvalho',
    unitId: '3',
    unitName: 'Filial 02',
    versionCode: 'SOJA26/27.02',
    items: const [
      SimulationItem(productId: '5', productName: 'NPK', unit: 'saco 50kg', quantity: 48),
    ],
    simulatedSacks: 48,
    seasonId: seasonId,
    grainId: grainId,
    grainName: grainId == '1' ? 'Soja' : 'Milho',
    plantedAreaHa: 120,
    createdAt: DateTime(2026, 3, 1),
    updatedAt: DateTime(2026, 3, 2),
  );

  /// Uma versão vigente como o consultor a recebe: SEM R$, com a tabela já
  /// convertida em sacas da cultura dela.
  BarterVersionModel versao({
    required String id,
    required String seasonId,
    required String season,
    required String grainId,
    required String grain,
  }) => BarterVersionModel(
    id: id,
    code: '${grain.toUpperCase()}.01',
    number: 1,
    seasonId: seasonId,
    seasonCode: grain.toUpperCase(),
    seasonName: season,
    grainId: grainId,
    grainName: grain,
    grainUnit: 'saca 60kg',
    estimatedYield: 60,
    showsCurrency: false,
    status: 'active',
    isOpen: true,
    startsAt: DateTime(2026, 2, 1),
    prices: const [
      VersionPriceModel(productId: '5', productName: 'NPK 04-14-08', unit: 'saco 50kg', perUnit: 1),
    ],
  );

  final soja = versao(id: 'v1', seasonId: '3', season: 'Soja 26/27', grainId: '1', grain: 'Soja');
  final milho = versao(id: 'v2', seasonId: '4', season: 'Milho 2027', grainId: '2', grain: 'Milho');

  setUp(() {
    AppData.currentUser = consultor();
    AppData.producers = [produtor()];
    AppData.units = [
      UnitModel(id: '3', name: 'Filial 02', city: 'Marialva/PR', createdAt: DateTime(2020, 1, 1)),
    ];
    AppData.inputs = [
      const ProductModel(
        id: '5',
        name: 'NPK 04-14-08',
        unit: 'saco 50kg',
        currentPrice: 100,
        type: ProductType.input,
        priceHistory: [],
      ),
    ];
    AppData.currentVersions = [soja, milho];
  });

  tearDown(() {
    AppData.currentUser = null;
    AppData.producers = [];
    AppData.units = [];
    AppData.inputs = [];
    AppData.currentVersions = [];
  });

  Future<void> abrir(WidgetTester tester, {BarterSimulation? simulation}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: NewBarterScreen(consultant: consultor(), simulation: simulation)),
    );
    await tester.pumpAndSettle();
  }

  /// DUAS CULTURAS ABERTAS: a permuta nova começa escolhendo em qual delas.
  testWidgets('com duas culturas, a primeira etapa é escolher a cultura', (tester) async {
    await abrir(tester);

    expect(find.textContaining('escolha a cultura'), findsOneWidget);
    expect(find.text('Soja 26/27'), findsOneWidget);
    expect(find.text('Milho 2027'), findsOneWidget);
  });

  testWidgets('escolhida a cultura, a faixa diz em que ela será paga', (tester) async {
    await abrir(tester);

    await tester.tap(find.text('Milho 2027'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pagamento em milho'), findsOneWidget);
    // E dá para voltar atrás: com duas culturas, a escolha continua à mão.
    expect(find.text('Trocar cultura'), findsOneWidget);
  });

  /// UMA CULTURA SÓ NÃO É ESCOLHA: ela já é a resposta.
  testWidgets('com uma cultura só, não há etapa de escolha', (tester) async {
    AppData.currentVersions = [soja];
    await abrir(tester);

    expect(find.textContaining('escolha a cultura'), findsNothing);
    expect(find.textContaining('Pagamento em soja'), findsOneWidget);
    expect(find.text('Trocar cultura'), findsNothing);
  });

  /// A SIMULAÇÃO GUARDA A CULTURA e a área: ela sobrevive ao aparelho ficar no
  /// bolso até o envio, e volta na cultura em que foi montada.
  testWidgets('a simulação retomada abre na cultura e com a área dela', (tester) async {
    await abrir(tester, simulation: simulacao(seasonId: '4', grainId: '2'));

    expect(find.textContaining('Pagamento em milho'), findsOneWidget);
    expect(find.text('Área plantada de milho (ha)'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });

  /// A SIMULAÇÃO DO APP ANTERIOR só guardou o grão: ela abre na versão vigente
  /// daquele grão.
  testWidgets('a simulação antiga, só com o grão, abre na cultura dele', (tester) async {
    await abrir(tester, simulation: simulacao(seasonId: '', grainId: '1'));

    expect(find.textContaining('Pagamento em soja'), findsOneWidget);
  });
}
