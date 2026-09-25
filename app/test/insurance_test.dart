import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/data/app_data.dart';
import 'package:agrobarter_app/models/models.dart';

/// O SEGURO DO PRODUTOR visto do lado do app.
///
/// Dois pontos são travados aqui, e eles são de naturezas diferentes:
///
/// 1. **a conta** — `custo = área × taxa da praça` é a mesma do servidor
///    (`insuranceCostFor`), com o mesmo arredondamento. Ela existe nos dois
///    lados porque a prévia precisa bater, ao centavo, com o que vai ser
///    gravado; se elas divergirem, o consultor fala um número ao produtor e o
///    registro grava outro;
/// 2. **o parse** — um campo novo do servidor que o app lê errado (ou deixa de
///    ler) é uma tela que mente sobre uma permuta que existe.
void main() {
  group('InsuranceRateModel', () {
    /// A lente da RETAGUARDA: a taxa chega em R$ por hectare.
    InsuranceRateModel comReais() => InsuranceRateModel.fromJson({
          'id': 1,
          'city': 'Maringá/PR',
          'valuePerHa': 85.0,
          'note': 'Soja 2026',
          'updatedAt': '2026-01-09T00:00:00.000Z',
        });

    /// A lente do CONSULTOR: sem R$, e com a taxa já convertida em sacas.
    InsuranceRateModel emSacas() => InsuranceRateModel.fromJson({
          'id': 1,
          'city': 'Maringá/PR',
          'sacksPerHa': 85.0 / 148.5,
        });

    test('a conta é área × taxa, com a precisão do comprovante', () {
      expect(comReais().costFor(120), 10200);
      expect(comReais().costFor(0), 0);
    });

    /// O mesmo caso do teste do servidor, e de propósito: é o arredondamento a
    /// centavos que precisa coincidir nos dois lados.
    test('arredonda a centavos como o servidor', () {
      final rate = InsuranceRateModel.fromJson({'city': 'X/PR', 'valuePerHa': 92.5});
      expect(rate.costFor(133.33), 12333.03);
    });

    /// Zero não é "seguro de graça": é "não dá para calcular". Quem decide o
    /// que fazer com a ausência é o registro, que recusa nomeando o município.
    test('sem área ou sem taxa, não inventa custo', () {
      expect(comReais().costFor(-10), 0);
      expect(InsuranceRateModel.fromJson({'city': 'X/PR', 'valuePerHa': 0}).costFor(120), 0);
    });

    /// A LENTE: o consultor não recebe R$ nenhum, e lê a mesma taxa em sacas.
    /// `showsCurrency` é o que separa "R$ 0,00" de "esta resposta não traz R$".
    test('quem não vê R\$ recebe a taxa em sacas por hectare', () {
      final rate = emSacas();
      expect(rate.showsCurrency, isFalse);
      expect(rate.valuePerHa, 0);
      expect(rate.sacksFor(120), closeTo(120 * 85 / 148.5, 0.0001));
      // E a conta em R$ não é inventada a partir do que não veio.
      expect(rate.costFor(120), 0);
    });
  });

  group('A permuta com seguro', () {
    Map<String, dynamic> barterJson({
      bool comSeguro = true,
      bool showsCurrency = true,
    }) => {
          'code': 'PRM-2026-010',
          'versionCode': 'S2026.02',
          'consultantName': 'João Silva',
          'producerName': 'Antônio Carvalho',
          'status': 'pending',
          'createdAt': '2026-01-10T00:00:00.000Z',
          if (comSeguro) 'insuranceCity': 'Maringá/PR',
          if (comSeguro && showsCurrency) 'insuranceRatePerHa': 85.0,
          'items': [
            {
              'kind': 'grain',
              'productId': 1,
              'productName': 'Soja',
              'unit': 'saca 60kg',
              'quantity': 149.1313,
              if (showsCurrency) 'unitValue': 148.5,
            },
            {
              'kind': 'input',
              'productId': 5,
              'productName': 'NPK',
              'unit': 'saco 50kg',
              'quantity': 48,
              if (showsCurrency) 'unitValue': 115.0,
            },
            if (comSeguro)
              {
                'kind': 'input',
                'productId': null,
                'productName': 'Seguro agrícola — Maringá/PR',
                'unit': 'ha',
                'quantity': 120,
                if (showsCurrency) 'unitValue': 85.0,
                'insurance': true,
              },
          ],
        };

    /// A LINHA DO SEGURO chega como insumo — ela forma custo como tudo o mais
    /// que a empresa adianta —, e o que a distingue é a marca. Um `kind`
    /// próprio obrigaria toda soma do app a aprender uma terceira espécie de
    /// linha, e a primeira que esquecesse deixaria o seguro fora da conta.
    test('a linha do seguro é insumo, com a marca que a explica', () {
      final barter = BarterModel.fromJson(barterJson());

      expect(barter.hasInsurance, isTrue);
      expect(barter.insuranceCity, 'Maringá/PR');

      final seguro = barter.insuranceItem;
      expect(seguro, isNotNull);
      expect(seguro!.insurance, isTrue);
      expect(seguro.productName, 'Seguro agrícola — Maringá/PR');
      // A conta fica legível na própria linha: 120 ha × R$ 85,00.
      expect(seguro.quantity, 120);
      expect(seguro.unitValue, 85);
      expect(seguro.total, 10200);

      // E ele SOMA no custo, junto com os insumos: 48 × 115 + 10.200.
      expect(barter.inputCost, closeTo(5520 + 10200, 0.001));
    });

    /// A TAXA é R$, e R$ não atravessa a lente do consultor. A PRAÇA
    /// atravessa: ela é o que explica de onde o valor saiu.
    test('o consultor recebe a praça e não a taxa', () {
      final barter = BarterModel.fromJson(barterJson(showsCurrency: false));

      expect(barter.insuranceCity, 'Maringá/PR');
      expect(barter.insuranceRatePerHa, isNull);
      expect(barter.insuranceItem!.hasUnitValue, isFalse);
    });

    test('permuta sem seguro não tem linha nem praça', () {
      final barter = BarterModel.fromJson(barterJson(comSeguro: false));

      expect(barter.hasInsurance, isFalse);
      expect(barter.insuranceItem, isNull);
      expect(barter.inputs.any((item) => item.insurance), isFalse);
    });
  });

  /// A PRAÇA DO PRODUTOR na base — a parte que decide se a prévia da tela
  /// mostra o seguro ou anuncia uma recusa que não vai acontecer.
  ///
  /// A regra é a mesma do servidor (`sameCity`), e ela existe por um motivo
  /// concreto: a planilha da seguradora é toda de um estado só e traz
  /// "TUPANCIRETÃ", enquanto o cadastro do produtor traz "Tupanciretã/RS".
  group('AppData.insuranceRateFor', () {
    InsuranceRateModel rate(String city) =>
        InsuranceRateModel.fromJson({'id': city, 'city': city, 'valuePerHa': 85.0});

    tearDown(() => AppData.insuranceRates = []);

    test('acha a praça sem UF a partir do produtor cadastrado com ela', () {
      AppData.insuranceRates = [rate('TUPANCIRETÃ')];

      expect(AppData.insuranceRateFor('Tupanciretã/RS')?.city, 'TUPANCIRETÃ');
      expect(AppData.insuranceRateFor('tupancireta')?.city, 'TUPANCIRETÃ');
    });

    test('ignora acento, caixa e espaço em volta da barra', () {
      AppData.insuranceRates = [rate('Campo Mourão/PR')];

      expect(AppData.insuranceRateFor('campo mourao / pr')?.city, 'Campo Mourão/PR');
    });

    /// Dois estados declarados são duas praças de verdade — e o produtor que
    /// disse o dele recebe a dele.
    test('duas UFs diferentes são duas praças', () {
      AppData.insuranceRates = [rate('Bom Jesus/RS'), rate('Bom Jesus/SC')];

      expect(AppData.insuranceRateFor('Bom Jesus/SC')?.city, 'Bom Jesus/SC');
      // Sem dizer o estado, não há como escolher: devolve null, e a tela avisa
      // que falta praça em vez de cotar o seguro do estado errado.
      expect(AppData.insuranceRateFor('Bom Jesus'), isNull);
    });

    test('município que não está na base devolve null', () {
      AppData.insuranceRates = [rate('TUPANCIRETÃ')];

      expect(AppData.insuranceRateFor('Tupanciretã do Sul/RS'), isNull);
      expect(AppData.insuranceRateFor(''), isNull);
    });
  });

  group('A versão do Barter', () {
    test('diz se o lançamento leva seguro', () {
      Map<String, dynamic> json(bool comSeguro) => {
            'id': 4,
            'code': 'S2026.02',
            'number': 2,
            'grainName': 'Soja',
            'grainPrice': 148.5,
            'status': 'active',
            'isOpen': true,
            'startsAt': '2026-01-08T00:00:00.000Z',
            'prices': const [],
            if (comSeguro) 'insuranceRequired': true,
          };

      expect(BarterVersionModel.fromJson(json(true)).insuranceRequired, isTrue);
      // AUSENTE vale `false`, e é a verdade sobre as versões anteriores ao
      // campo: elas foram lançadas sem seguro nenhum.
      expect(BarterVersionModel.fromJson(json(false)).insuranceRequired, isFalse);
    });
  });
}
