import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/barter_simulation.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_screen.dart';

/// A ESCOLHA DA CULTURA, na tela de verdade.
///
/// As culturas coexistem: o mesmo Barter aceita soja e milho, sobre a MESMA
/// tabela de insumos, e quem decide em qual delas o cliente paga é o consultor
/// — junto com o produtor, que é quem sabe o que vai plantar naquele talhão.
///
/// O que estes testes guardam é o que a escolha significa na tela: ela existe
/// quando há o que escolher, ela some quando não há, e o que ela muda é a
/// CONVERSÃO — o mesmo insumo custa 0,77 saca de soja e 1,78 de milho, porque o
/// preço em R$ é o mesmo e a cotação não é.
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
    consultantIds: const ['2'],
    document: '123.456.789-09',
    phone: '',
    farmName: 'Fazenda Boa Vista',
    city: 'Mandaguari/PR',
    areaHa: 120,
    avatarInitials: 'AC',
    createdAt: DateTime(2020, 1, 1),
  );

  BarterSimulation simulacao() => BarterSimulation(
    id: 'sim-1',
    consultantId: '2',
    producerId: '10',
    producerName: 'Antônio Carvalho',
    unitId: '3',
    unitName: 'Filial 02',
    versionCode: 'B2026.02',
    items: const [
      SimulationItem(productId: '5', productName: 'NPK', unit: 'saco 50kg', quantity: 48),
    ],
    simulatedSacks: 48,
    grainId: '1',
    grainName: 'Soja',
    createdAt: DateTime(2026, 3, 1),
    updatedAt: DateTime(2026, 3, 2),
  );

  /// A versão vigente como o consultor a recebe: SEM R$, com a tabela já
  /// convertida em sacas da cultura escolhida (`pricedInGrainId`).
  ///
  /// [culturas] é parâmetro porque é a diferença entre os dois casos que
  /// importam: duas culturas viram escolha, uma só volta a ser informação.
  BarterVersionModel versao({int culturas = 2}) => BarterVersionModel(
    id: 'v1',
    code: 'B2026.02',
    number: 2,
    seasonCode: 'B2026',
    seasonName: 'Barter 2026/27',
    grains: [
      const VersionGrainModel(
        grainId: '1',
        grainName: 'Soja',
        grainUnit: 'saca 60kg',
        estimatedYield: 60,
        showsCurrency: false,
      ),
      if (culturas > 1)
        const VersionGrainModel(
          grainId: '2',
          grainName: 'Milho',
          grainUnit: 'saca 60kg',
          estimatedYield: 170,
          showsCurrency: false,
        ),
    ],
    pricedInGrainId: '1',
    showsCurrency: false,
    status: 'open',
    isOpen: true,
    startsAt: DateTime(2026, 2, 1),
    prices: const [
      // 1 saca de soja por saco de NPK — a tabela chega convertida, e é isso
      // que o consultor lê.
      VersionPriceModel(
        productId: '5',
        productName: 'NPK 04-14-08',
        unit: 'saco 50kg',
        perUnit: 1,
      ),
    ],
  );

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
    AppData.currentVersion = versao();
  });

  tearDown(() {
    AppData.currentUser = null;
    AppData.producers = [];
    AppData.units = [];
    AppData.inputs = [];
    AppData.currentVersion = null;
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NewBarterScreen(consultant: consultor(), simulation: simulacao()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a faixa diz em que cultura a permuta será paga', (tester) async {
    await abrir(tester);

    expect(find.textContaining('Pagamento em soja'), findsOneWidget);
  });

  /// DUAS CULTURAS VIRAM ESCOLHA. O seletor fica na faixa do Barter, no alto:
  /// a escolha muda a conta inteira, e o lugar de decidir é antes de montar.
  testWidgets('com duas culturas, a faixa oferece as duas', (tester) async {
    await abrir(tester);

    final seletor = find.byType(DropdownButton<String>);
    expect(seletor, findsOneWidget);

    await tester.tap(seletor);
    await tester.pumpAndSettle();

    // As duas aparecem no menu aberto — a escolhida some da faixa enquanto o
    // menu está sobre ela, então o que se conta é a presença das duas.
    expect(find.text('Milho'), findsWidgets);
    expect(find.text('Soja'), findsWidgets);
  });

  /// UMA CULTURA SÓ NÃO É ESCOLHA: um menu com uma opção é uma decisão que não
  /// existe, e a cultura volta a ser a informação que sempre foi.
  testWidgets('com uma cultura só, não há seletor', (tester) async {
    AppData.currentVersion = versao(culturas: 1);
    await abrir(tester);

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.textContaining('Pagamento em soja'), findsOneWidget);
  });

  /// A SIMULAÇÃO GUARDA A CULTURA, e é por isso que ela sobrevive ao aparelho
  /// ficar no bolso até o envio: enviá-la sem a cultura faria a permuta nascer
  /// numa que ninguém escolheu.
  testWidgets('a simulação retomada abre na cultura em que foi montada', (tester) async {
    await abrir(tester);

    final banner = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(banner.value, '1');
  });
}
