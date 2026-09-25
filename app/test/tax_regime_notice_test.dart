import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/barter_simulation.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_screen.dart';

/// O AVISO DO FUNRURAL, na tela de verdade.
///
/// O regime não é escolha de quem fecha a permuta: é a opção formal que o
/// produtor fez perante o fisco, e ela mora no cadastro dele. A etapa 3 LÊ esse
/// cadastro e diz, em voz alta, qual imposto vai incidir e quanto ele dá em
/// sacas. Enquanto isto foi um seletor de duas opções, a tela convidava a marcar
/// a alíquota menor numa permuta específica.
///
/// Estes testes rodam a etapa 3 inteira num telefone estreito, que é onde o
/// aviso tem chance de estourar a linha.
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

  /// Antônio é PF: 1,63% na comercialização, 0,20% na folha.
  ProducerModel produtor({
    String document = '123.456.789-09',
    TaxRegime taxRegime = TaxRegime.comercializacao,
  }) => ProducerModel(
    id: '10',
    name: 'Antônio Carvalho',
    consultantIds: const ['2'],
    document: document,
    phone: '',
    farmName: 'Fazenda Boa Vista',
    city: 'Mandaguari/PR',
    areaHa: 120,
    taxRegime: taxRegime,
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
    grainName: 'Soja',
    taxRegime: TaxRegime.comercializacao,
    createdAt: DateTime(2026, 3, 1),
    updatedAt: DateTime(2026, 3, 2),
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
    AppData.currentVersion = BarterVersionModel(
      id: 'v1',
      code: 'B2026.02',
      number: 2,
      seasonCode: 'B2026',
      seasonName: 'Barter 2026',
      grains: const [
        VersionGrainModel(
          grainId: '1',
          grainName: 'Soja',
          grainUnit: 'saca 60kg',
          price: 100,
          estimatedYield: 60,
        ),
      ],
      pricedInGrainId: '1',
      status: 'open',
      isOpen: true,
      startsAt: DateTime(2026, 2, 1),
      prices: const [
        VersionPriceModel(
          productId: '5',
          productName: 'NPK 04-14-08',
          unit: 'saco 50kg',
          perUnit: 100,
        ),
      ],
    );
  });

  tearDown(() {
    AppData.currentUser = null;
    AppData.producers = [];
    AppData.units = [];
    AppData.inputs = [];
    AppData.currentVersion = null;
    AppData.classes = [];
  });

  /// Abre a etapa 3 numa tela de [largura] por 800.
  ///
  /// A largura é parâmetro porque é ela que expõe o defeito de layout: um `Text`
  /// solto numa `Row` só estoura quando o conteúdo passa da tela, e num
  /// simulador largo ele nunca passa.
  Future<void> abrirEtapa3(WidgetTester tester, {double largura = 360}) async {
    tester.view.physicalSize = Size(largura, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NewBarterScreen(consultant: consultor(), simulation: simulacao()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('o aviso diz o regime do cadastro e a alíquota dele', (tester) async {
    await abrirEtapa3(tester);

    // Antônio é PF e está na comercialização: 1,63%. O aviso diz DE ONDE o
    // número vem, que é o que faz dele um fato e não uma escolha.
    expect(find.textContaining('No cadastro, este produtor recolhe'), findsOneWidget);
    expect(find.textContaining('1,63%'), findsOneWidget);
  });

  /// NÃO HÁ o que trocar aqui: corrigir o regime é ato do admin, no cadastro do
  /// produtor, e vale da próxima permuta em diante.
  testWidgets('a etapa 3 não oferece trocar o imposto', (tester) async {
    await abrirEtapa3(tester);

    expect(find.byType(SegmentedButton<TaxRegime>), findsNothing);
    expect(find.text('Folha'), findsNothing);
  });

  testWidgets('o aviso diz quanto o imposto dá em sacas', (tester) async {
    await abrirEtapa3(tester);

    // 48 sacos x R$ 100 = R$ 4.800; a R$ 100 a saca, 48 sacas. 1,63% disso são
    // 0,78 saca, que o formato do app arredonda para uma casa. O consultor não
    // vê R$ em lugar nenhum: o imposto sai em grão, como o resto da permuta.
    expect(find.textContaining('+ 0,8 sc soja'), findsOneWidget);
  });

  /// O CABEÇALHO DO PRODUTOR não pode estourar a linha.
  ///
  /// "1.200 ha • Mandaguari/PR" vinha num `Text` solto dentro de uma `Row`: sem
  /// largura máxima o `ellipsis` não tem onde cortar, e a faixa saía com 127
  /// pixels de listra vermelha por cima num telefone de 360. O arquivo já tinha
  /// consertado exatamente isso no rodapé — este teste é para não voltar pela
  /// terceira porta.
  ///
  /// Roda em 320 e em 360: o defeito é de largura, e um teste que só olha o
  /// aparelho grande não veria nenhum dos dois casos.
  for (final largura in [320.0, 360.0]) {
    testWidgets('a etapa 3 cabe na tela de ${largura.toInt()} sem estourar', (tester) async {
      await abrirEtapa3(tester, largura: largura);

      // Nome longo e cidade longa é o pior caso real, não um inventado.
      expect(find.textContaining('Mandaguari/PR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  /// PF ou PJ não é pergunta: sai do documento do produtor, e muda a alíquota.
  testWidgets('CNPJ paga outro percentual, e o aviso mostra o dele', (tester) async {
    AppData.producers = [produtor(document: '12.345.678/0001-90')];
    await abrirEtapa3(tester);

    expect(find.textContaining('2,23%'), findsOneWidget);
    expect(find.textContaining('1,63%'), findsNothing);
  });

  /// O REGIME É DO PRODUTOR, e a permuta nasce com o dele.
  ///
  /// A opção pela folha é feita uma vez, perante o fisco, e vale para todas as
  /// entregas — perguntá-la a cada fechamento era pedir ao consultor que
  /// respondesse de memória, e a segunda permuta do mesmo produtor saía num
  /// regime diferente da primeira sem nada ter mudado no mundo.
  ///
  /// A simulação retomada é o caso contrário e continua valendo: ela carrega a
  /// escolha do dia em que foi montada, e retomá-la não pode trocá-la por
  /// baixo de quem já decidiu.
  testWidgets('a permuta nasce no regime do cadastro do produtor', (tester) async {
    AppData.producers = [produtor(taxRegime: TaxRegime.folha)];
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Sem simulação: a tela começa na etapa 1, e o regime entra junto com o
    // produtor escolhido.
    await tester.pumpWidget(MaterialApp(home: NewBarterScreen(consultant: consultor())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Antônio Carvalho'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Filial 02').first);
    await tester.pumpAndSettle();

    // Um insumo qualquer, para o rodapé do imposto aparecer.
    await tester.enterText(find.byType(TextField).last, '10');
    await tester.pumpAndSettle();

    // A FOLHA, sem ninguém ter escolhido nada: ela veio do cadastro junto com o
    // produtor. Para o CPF dele, sobra o Senar de 0,20%.
    expect(find.textContaining('folha'), findsOneWidget);
    expect(find.textContaining('0,20%'), findsOneWidget);
  });
}
