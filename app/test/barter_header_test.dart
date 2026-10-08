import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/barter_simulation.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_screen.dart';
import 'package:agrobarter_app/widgets/common_widgets.dart';

/// O CABEÇALHO DA MONTAGEM — e quem pode montar.
///
/// O que estes testes guardam:
///
/// * a identificação é o MESMO componente do resto do app, numa linha só;
/// * o seguro mora no cabeçalho, pago em grão, pelo município que o consultor
///   ESCOLHE — e trocar o município muda a conta;
/// * o valor do grão aparece UMA vez (era o painel sem o seguro e o rodapé com
///   ele, dois números para a mesma pergunta);
/// * o ADMIN gera permuta na mesma tela, e ela é do consultor do produtor.
void main() {
  UserModel usuario({required String id, required String name, required UserRole role}) => UserModel(
    id: id,
    name: name,
    email: '$id@coop.test',
    phone: '',
    branch: 'Filial 02',
    role: role,
    avatarInitials: name.substring(0, 2).toUpperCase(),
    createdAt: DateTime(2026, 1, 1),
  );

  final consultor = usuario(id: '2', name: 'João Silva', role: UserRole.consultant);
  final admin = usuario(id: '1', name: 'Marta Admin', role: UserRole.admin);

  ProducerModel produtor({String id = '10', String name = 'Antônio Carvalho', String? consultantId = '2'}) =>
      ProducerModel(
        id: id,
        name: name,
        consultantId: consultantId,
        document: '123.456.789-09',
        phone: '',
        farmName: 'Fazenda Boa Vista',
        city: 'Mandaguari/PR',
        taxRegime: TaxRegime.comercializacao,
        avatarInitials: name.substring(0, 2).toUpperCase(),
        createdAt: DateTime(2020, 1, 1),
      );

  InsuranceRateModel taxa(String city, double valuePerHa) =>
      InsuranceRateModel(id: city, city: city, valuePerHa: valuePerHa);

  /// 48 sacos a R$ 100, com a saca a R$ 100: 48 sacas de insumo. O seguro de
  /// 120 ha a R$ 10/ha (Mandaguari) é R$ 1.200 — 12 sacas; a R$ 20/ha (Campo
  /// Mourão), 24 sacas.
  BarterSimulation simulacao() => BarterSimulation(
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
    seasonId: '3',
    grainId: '1',
    grainName: 'Soja',
    plantedAreaHa: 120,
    createdAt: DateTime(2026, 3, 1),
    updatedAt: DateTime(2026, 3, 2),
  );

  setUp(() {
    AppData.currentUser = consultor;
    AppData.consultants = [consultor];
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
    AppData.insuranceRates = [taxa('Mandaguari/PR', 10), taxa('Campo Mourão/PR', 20)];
    AppData.currentVersions = [
      BarterVersionModel(
        id: 'v1',
        code: 'SOJA26/27.02',
        number: 2,
        seasonId: '3',
        seasonCode: 'SOJA26/27',
        seasonName: 'Soja 26/27',
        grainId: '1',
        grainName: 'Soja',
        grainUnit: 'saca 60kg',
        grainPrice: 100,
        estimatedYield: 60,
        status: 'open',
        isOpen: true,
        insurancePolicy: InsurancePolicy.required,
        startsAt: DateTime(2026, 2, 1),
        prices: const [
          VersionPriceModel(productId: '5', productName: 'NPK 04-14-08', unit: 'saco 50kg', perUnit: 100),
        ],
      ),
    ];
  });

  tearDown(() {
    AppData.currentUser = null;
    AppData.consultants = [];
    AppData.producers = [];
    AppData.units = [];
    AppData.inputs = [];
    AppData.insuranceRates = [];
    AppData.currentVersions = [];
  });

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: tela));
    await tester.pumpAndSettle();
  }

  /// O total da permuta como o cabeçalho o escreve: o número e o grão.
  Finder total(String sacks) => find.text('$sacks soja', findRichText: true);

  testWidgets('a identificação é a da permuta, numa linha só', (tester) async {
    await abrir(tester, NewBarterScreen(consultant: consultor, simulation: simulacao()));

    final identity = tester.widget<BarterIdentity>(find.byType(BarterIdentity));
    expect(identity.singleLine, isTrue);
    expect(find.text('Antônio Carvalho'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.textContaining('Soja 26/27 •'), findsOneWidget);
    expect(find.textContaining('Filial 02'), findsOneWidget);
  });

  testWidgets('o valor do grão aparece uma vez, com o seguro dentro', (tester) async {
    await abrir(tester, NewBarterScreen(consultant: consultor, simulation: simulacao()));

    // 48 de insumo + 12 do seguro de Mandaguari, a praça do cadastro.
    expect(total('60 sc'), findsOneWidget);
    expect(find.text('+ 12 sc soja de seguro'), findsOneWidget);
    // Nem o painel antigo (sem o seguro) nem a linha "Entregar:" do rodapé.
    expect(find.byType(BarterBalanceBar), findsNothing);
    expect(find.textContaining('Entregar:'), findsNothing);
  });

  testWidgets('o consultor escolhe o município do seguro, e ele refaz a conta', (tester) async {
    await abrir(tester, NewBarterScreen(consultant: consultor, simulation: simulacao()));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Campo Mourão/PR').last);
    await tester.pumpAndSettle();

    expect(find.text('+ 24 sc soja de seguro'), findsOneWidget);
    expect(total('72 sc'), findsOneWidget);
  });

  testWidgets('município sem taxa avisa que é preciso escolher outro', (tester) async {
    AppData.insuranceRates = [taxa('Campo Mourão/PR', 20)];
    await abrir(tester, NewBarterScreen(consultant: consultor, simulation: simulacao()));

    expect(find.textContaining('Mandaguari/PR não tem valor por hectare'), findsOneWidget);
  });

  group('o admin gera permuta', () {
    testWidgets('escolhe entre os produtores que têm consultor', (tester) async {
      AppData.currentUser = admin;
      AppData.producers = [
        produtor(),
        produtor(id: '11', name: 'Helena Prado', consultantId: null),
      ];
      await abrir(tester, NewBarterScreen(consultant: admin));

      expect(find.textContaining('Gerar'), findsWidgets);
      expect(find.text('Antônio Carvalho'), findsOneWidget);
      expect(find.text('Helena Prado'), findsNothing);
    });

    testWidgets('a permuta é do consultor do produtor', (tester) async {
      AppData.currentUser = admin;
      await abrir(tester, NewBarterScreen(consultant: admin));

      await tester.tap(find.text('Antônio Carvalho'));
      await tester.pumpAndSettle();

      final identity = tester.widget<BarterIdentity>(find.byType(BarterIdentity));
      expect(identity.consultantName, 'João Silva');
      expect(find.text('Marta Admin'), findsNothing);
    });
  });
}
