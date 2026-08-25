import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/barter_simulation.dart';
import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/screens/barter_screen.dart';

/// O SELETOR DO FUNRURAL, na tela de verdade.
///
/// A escolha do regime não é preferência de exibição: ela é gravada na permuta
/// e vira o `taxRate` congelado do comprovante. Enquanto os segmentos diziam só
/// a alíquota, o nome da opção não selecionada ficava invisível e descobri-lo
/// custava tocar nela — que é o mesmo gesto de declará-la.
///
/// Estes testes rodam a etapa 3 inteira num telefone estreito, que é onde os
/// dois rótulos por segmento têm chance de estourar a linha.
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
  ProducerModel produtor({String document = '123.456.789-09'}) => ProducerModel(
    id: '10',
    name: 'Antônio Carvalho',
    consultantIds: const ['2'],
    document: document,
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
    versionCode: 'S2026.02',
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
      code: 'S2026.02',
      number: 2,
      seasonCode: 'S2026',
      seasonName: 'Safra 2026',
      grainId: '1',
      grainName: 'Soja',
      grainUnit: 'saca 60kg',
      grainPrice: 100,
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

  testWidgets('cada segmento diz a alíquota E o nome da forma', (tester) async {
    await abrirEtapa3(tester);

    // As duas alíquotas de PF, visíveis sem tocar em nada: é o percentual que a
    // pessoa do outro lado do balcão pergunta.
    expect(find.text('1,63%'), findsOneWidget);
    expect(find.text('0,20%'), findsOneWidget);

    // E o nome de CADA UMA, inclusive o da que não está marcada — descobri-lo
    // não pode custar o gesto que a declara.
    expect(find.text('Comercialização'), findsOneWidget);
    expect(find.text('Folha'), findsOneWidget);
  });

  testWidgets('a linha de baixo explica a forma marcada, além do quanto', (tester) async {
    await abrirEtapa3(tester);

    // 48 sacos × R$ 100 = R$ 4.800; a R$ 100 a saca, 48 sacas. 1,63% disso são
    // 0,78 saca, que o formato do app arredonda para uma casa. O consultor não
    // vê R$ em lugar nenhum — o imposto sai em grão, como o resto da permuta.
    expect(find.textContaining('+ 0,8 sc soja de Funrural/Senar'), findsOneWidget);
    // `description` deixou de ser código morto: era a única frase do app que
    // dizia a diferença entre as duas formas, e ela não aparecia em tela alguma.
    expect(find.textContaining('O Funrural sai da receita de cada venda'), findsOneWidget);
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

  testWidgets('CNPJ troca as duas alíquotas de uma vez', (tester) async {
    AppData.producers = [produtor(document: '12.345.678/0001-90')];
    await abrirEtapa3(tester);

    expect(find.text('2,23%'), findsOneWidget);
    expect(find.text('0,25%'), findsOneWidget);
    expect(find.text('1,63%'), findsNothing);
  });
}
