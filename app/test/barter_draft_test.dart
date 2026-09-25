import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/barter_draft.dart';

/// A PERMUTA SENDO MONTADA — as regras que travam (ou liberam) o envio, sem
/// abrir a tela.
///
/// Elas eram ~180 linhas de getters dentro do `State` do construtor de permuta,
/// e só podiam ser exercitadas montando o widget inteiro. Cada caso aqui é uma
/// decisão que o consultor sente na mão: o que é permutável nesta gestão, o
/// mínimo por hectare que ele não consegue baixar, a régua da pasta que segura
/// o envio, e o seguro da praça que ainda não está na base.
void main() {
  ProductModel insumo(String id, String name, {double requiredPerHa = 0, String? classId}) =>
      ProductModel(
        id: id,
        name: name,
        unit: 'saco 50kg',
        currentPrice: 100,
        type: ProductType.input,
        requiredPerHa: requiredPerHa,
        classId: classId,
        priceHistory: const [],
      );

  ProducerModel produtor({double areaHa = 100, String city = 'Maringá/PR'}) => ProducerModel(
        id: '10',
        name: 'Antônio Carvalho',
        consultantIds: const ['2'],
        document: '123.456.789-09',
        phone: '',
        farmName: 'Fazenda Boa Vista',
        city: city,
        areaHa: areaHa,
        avatarInitials: 'AC',
        createdAt: DateTime(2020, 1, 1),
      );

  /// A versão como o CONSULTOR a recebe: sem R$, com a tabela já convertida em
  /// sacas da cultura escolhida. `perUnit` 1 deixa a conta legível — um saco de
  /// NPK custa uma saca de soja.
  BarterVersionModel versao({
    bool insuranceRequired = false,
    Map<String, double> prices = const {'5': 1, '6': 0.5},
  }) => BarterVersionModel(
        id: 'v1',
        code: 'B2026.02',
        number: 2,
        seasonCode: 'B2026',
        seasonName: 'Barter 2026/27',
        grains: const [
          VersionGrainModel(
            grainId: '1',
            grainName: 'Soja',
            grainUnit: 'saca 60kg',
            estimatedYield: 60,
            showsCurrency: false,
          ),
        ],
        pricedInGrainId: '1',
        showsCurrency: false,
        insuranceRequired: insuranceRequired,
        status: 'open',
        isOpen: true,
        startsAt: DateTime(2026, 2, 1),
        prices: [
          for (final entry in prices.entries)
            VersionPriceModel(
              productId: entry.key,
              productName: 'Insumo ${entry.key}',
              unit: 'saco 50kg',
              perUnit: entry.value,
            ),
        ],
      );

  ProductClassModel classe(
    String id,
    String name, {
    required ClassRuleType ruleType,
    required double ruleValue,
  }) => ProductClassModel(
        id: id,
        slug: name.toLowerCase(),
        name: name,
        position: 0,
        ruleType: ruleType,
        ruleValue: ruleValue,
      );

  /// [semProdutor] existe porque `producer: null` cairia no padrão do helper —
  /// e "antes de escolher o produtor" é justamente um dos estados que estes
  /// testes precisam montar.
  BarterDraft draft({
    BarterVersionModel? version,
    ProducerModel? producer,
    bool semProdutor = false,
    Map<String, double> quantities = const {},
    List<ProductModel>? inputs,
    List<ProductClassModel> classes = const [],
    InsuranceRateModel? insuranceRate,
    double offBarterCost = 0,
  }) => BarterDraft(
        version: version ?? versao(),
        producer: semProdutor ? null : (producer ?? produtor()),
        quantities: quantities,
        allInputs: inputs ?? [insumo('5', 'NPK'), insumo('6', 'Glifosato')],
        classes: classes,
        insuranceRate: insuranceRate,
        offBarterCost: offBarterCost,
      );

  group('o que está na mesa', () {
    /// INSUMO FORA DA TABELA DA VERSÃO não é permutável nesta gestão: ele existe
    /// no cadastro e não tem valor acordado, e o servidor recusa.
    test('o catálogo é o que esta versão precificou', () {
      final d = draft(
        inputs: [insumo('5', 'NPK'), insumo('6', 'Glifosato'), insumo('9', 'Fora da tabela')],
      );

      expect(d.catalog.map((p) => p.id), ['5', '6']);
      expect(d.productById('9'), isNull);
    });

    test('sem Barter aberto não há o que montar', () {
      final d = BarterDraft(
        version: null,
        producer: produtor(),
        quantities: const {'5': 10},
        allInputs: [insumo('5', 'NPK')],
        classes: const [],
      );

      expect(d.catalog, isEmpty);
      expect(d.inputsCost, 0);
      expect(d.sacksNeeded, 0);
      expect(d.canSubmit, isFalse);
    });
  });

  group('a conta', () {
    test('o custo é quantidade × valor da tabela, na moeda da lente', () {
      final d = draft(quantities: const {'5': 10, '6': 4});
      // 10 × 1 + 4 × 0,5.
      expect(d.inputsCost, 12);
    });

    /// O ITEM DE FORA DO BARTER e o SEGURO entram nas SACAS, e só ali: os dois
    /// são custo que a empresa adianta, e as réguas das pastas não os enxergam.
    test('o item de fora do Barter entra nas sacas', () {
      final d = draft(quantities: const {'5': 10}, offBarterCost: 5);
      expect(d.sacksNeeded, 15);
    });

    test('quantidade zerada não entra na conta', () {
      final d = draft(quantities: const {'5': 10, '6': 0});
      expect(d.pricedInputs.map((i) => i.productId), ['5']);
    });
  });

  group('o mínimo por hectare', () {
    test('é taxa × área do produtor', () {
      final d = draft(
        producer: produtor(areaHa: 120),
        inputs: [insumo('5', 'NPK', requiredPerHa: 0.4), insumo('6', 'Glifosato')],
      );

      expect(d.minimumFor('5'), 48);
      expect(d.minimumFor('6'), 0);
      expect(d.hasRequiredInputs, isTrue);
    });

    /// A PERMUTA JÁ NASCE com os obrigatórios no mínimo: começar em zero faria o
    /// consultor descobrir a exigência um a um, na recusa do envio.
    test('os obrigatórios entram pré-preenchidos no mínimo', () {
      final d = draft(
        producer: produtor(areaHa: 120),
        inputs: [insumo('5', 'NPK', requiredPerHa: 0.4), insumo('6', 'Glifosato')],
      );

      expect(d.requiredMinimums, {'5': 48.0});
    });

    test('a quantidade não desce abaixo do mínimo obrigatório', () {
      final d = draft(
        producer: produtor(areaHa: 120),
        inputs: [insumo('5', 'NPK', requiredPerHa: 0.4)],
      );

      expect(d.clampToMinimum('5', 10), 48);
      expect(d.clampToMinimum('5', 60), 60);
    });

    test('sem produtor escolhido não há área, e não há mínimo', () {
      final d = draft(
        semProdutor: true,
        inputs: [insumo('5', 'NPK', requiredPerHa: 0.4)],
      );

      expect(d.minimumFor('5'), 0);
    });
  });

  group('as réguas das pastas', () {
    final percentual = classe('c1', 'Fungicidas', ruleType: ClassRuleType.percentOfTotal, ruleValue: 20);
    final porHectare = classe('c2', 'Sementes', ruleType: ClassRuleType.valuePerHa, ruleValue: 2);

    test('a percentual mede a fatia da classe no custo total', () {
      final d = draft(
        quantities: const {'5': 10, '6': 4},
        inputs: [insumo('5', 'NPK', classId: 'c1'), insumo('6', 'Glifosato')],
        classes: [percentual],
      );

      // Custo 12; a classe pede 20% (2,4) e tem 10.
      expect(d.requiredOn(percentual), closeTo(2.4, 0.001));
      expect(d.isMet(percentual), isTrue);
      expect(d.unmetClasses, isEmpty);
    });

    test('a régua por hectare multiplica a área do produtor', () {
      final d = draft(
        producer: produtor(areaHa: 10),
        quantities: const {'5': 10},
        inputs: [insumo('5', 'NPK', classId: 'c2')],
        classes: [porHectare],
      );

      expect(d.requiredOn(porHectare), 20);
      expect(d.isMet(porHectare), isFalse);
      expect(d.unmetClasses.single.id, 'c2');
    });

    /// SEM PRODUTOR não há área, e a régua por hectare não tem base de cálculo.
    /// O servidor sempre tem — a permuta chega com produtor.
    test('sem produtor, a régua por hectare não exige nada', () {
      final d = draft(
        semProdutor: true,
        quantities: const {'5': 10},
        inputs: [insumo('5', 'NPK', classId: 'c2')],
        classes: [porHectare],
      );

      expect(d.requiredOn(porHectare), 0);
      expect(d.isMet(porHectare), isTrue);
    });

    /// A PERMUTA VAZIA fica em ZERO, e não em 100%: a régua percentual sobre
    /// custo zero dá exigência zero — cumprida na matemática —, mas "exigência
    /// atingida" antes do primeiro insumo é a tela dizendo que ele terminou sem
    /// ter começado.
    test('a permuta vazia não mostra régua cumprida', () {
      final d = draft(quantities: const {}, classes: [percentual]);

      expect(d.progressOn(percentual), 0);
      expect(d.isMetOnScreen(percentual), isFalse);
      // Mas a régua em si está cumprida — quem barra o envio vazio é a falta de
      // insumo, não a pasta.
      expect(d.isMet(percentual), isTrue);
    });
  });

  group('o seguro', () {
    final taxa = InsuranceRateModel(
      id: '1',
      city: 'Maringá/PR',
      valuePerHa: 2,
      sacksPerHa: 2,
      showsCurrency: false,
      updatedAt: DateTime(2026, 1, 1),
    );

    test('não se aplica quando o lançamento não leva seguro', () {
      final d = draft(quantities: const {'5': 10}, insuranceRate: taxa);

      expect(d.insuranceApplies, isFalse);
      expect(d.insuranceCost, 0);
      expect(d.sacksNeeded, 10);
    });

    test('aplicado, é área × taxa da praça e entra nas sacas', () {
      final d = draft(
        version: versao(insuranceRequired: true),
        producer: produtor(areaHa: 100),
        quantities: const {'5': 10},
        insuranceRate: taxa,
      );

      expect(d.insuranceCost, 200);
      expect(d.sacksNeeded, 210);
      expect(d.insuranceMissing, isFalse);
    });

    /// A PRAÇA FORA DA BASE é recusa certa no registro. Descobri-la aqui é de
    /// graça; descobri-la no envio é com o produtor do lado.
    test('praça sem taxa é falta que trava o envio', () {
      final d = draft(
        version: versao(insuranceRequired: true),
        quantities: const {'5': 10},
        insuranceRate: null,
      );

      expect(d.insuranceMissing, isTrue);
      expect(d.canSubmit, isFalse);
    });
  });

  group('pode enviar?', () {
    test('com produtor, insumo e réguas cumpridas, sim', () {
      expect(draft(quantities: const {'5': 10}).canSubmit, isTrue);
    });

    test('sem produtor ou sem insumo, não', () {
      expect(draft(semProdutor: true, quantities: const {'5': 10}).canSubmit, isFalse);
      expect(draft(quantities: const {}).canSubmit, isFalse);
    });

    test('com régua de pasta em aberto, não', () {
      final d = draft(
        producer: produtor(areaHa: 10),
        quantities: const {'5': 10},
        inputs: [insumo('5', 'NPK', classId: 'c2')],
        classes: [classe('c2', 'Sementes', ruleType: ClassRuleType.valuePerHa, ruleValue: 2)],
      );

      expect(d.canSubmit, isFalse);
    });
  });
}
