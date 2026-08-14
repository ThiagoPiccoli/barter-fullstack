import 'package:flutter_test/flutter_test.dart';
import 'package:agrobarter_app/models/models.dart';

/// O parse do JSON da API é o ponto em que uma mudança no servidor chega ao
/// app já instalado no aparelho de alguém. Um campo novo é inofensivo; um
/// VALOR novo num campo que o app converte para enum não é — e era aí que a
/// lista inteira parava de carregar.
void main() {
  Map<String, dynamic> barterJson({String status = 'pending'}) => {
        'code': 'PRM-2026-001',
        'versionCode': 'S2026.02',
        'consultantId': 2,
        'consultantName': 'João Silva',
        'consultantBranch': 'Filial 02',
        'producerId': 1,
        'producerName': 'Antônio Carvalho',
        'status': status,
        'createdAt': '2026-01-10T00:00:00.000Z',
        'items': [
          {
            'kind': 'grain',
            'productId': 1,
            'productName': 'Soja',
            'unit': 'saca 60kg',
            'quantity': 80.4444,
            'unitValue': 148.5,
            'unitCost': 0,
          },
          {
            'kind': 'input',
            'productId': 5,
            'productName': 'NPK',
            'unit': 'saco 50kg',
            'quantity': 48,
            'unitValue': 115.0,
            'unitCost': 90.0,
          },
        ],
      };

  Map<String, dynamic> versionJson({bool withGoals = false}) => {
        'id': 4,
        'code': 'S2026.02',
        'number': 2,
        'seasonCode': 'S2026',
        'seasonName': 'Soja 2026',
        'grainId': 1,
        'grainName': 'Soja',
        'grainUnit': 'saca 60kg',
        'grainPrice': 148.5,
        'status': 'active',
        'isOpen': true,
        'startsAt': '2026-01-08T00:00:00.000Z',
        'prices': [
          {
            'productId': 5,
            'productName': 'NPK',
            'unit': 'saco 50kg',
            'price': 115.0,
            'cost': 90.0,
          },
        ],
        if (withGoals) ...{
          'realized': {'sales': 5520.0, 'profit': 1200.0, 'sacks': 80.4, 'barters': 1},
          'goals': [
            {'kind': 'sales', 'target': 10000, 'realized': 5520.0, 'ratio': 0.552, 'met': false},
            {'kind': 'volumeExotico', 'target': 5, 'realized': 5, 'ratio': 1, 'met': true},
          ],
        },
      };

  group('BarterModel', () {
    test('separa itens por tipo e lê os status conhecidos', () {
      final barter = BarterModel.fromJson(barterJson(status: 'approved'));
      expect(barter.status, BarterStatus.approved);
      expect(barter.grains, hasLength(1));
      expect(barter.inputs, hasLength(1));
      expect(barter.inputCost, closeTo(5520.0, 0.001));
      expect(barter.referenceGrainName, 'Soja');
    });

    test('guarda a versão do Barter em que foi fechada e apura a margem', () {
      final barter = BarterModel.fromJson(barterJson(status: 'approved'));
      expect(barter.versionCode, 'S2026.02');
      // 48 × (115 − 90) = 1.200 — só os insumos entram; o grão é a moeda.
      expect(barter.profit, closeTo(1200.0, 0.001));
    });

    /// Permutas anteriores ao lançamento por versões não têm o campo. Elas
    /// continuam abrindo — o app só deixa de estampar a gestão.
    test('permuta sem versão (dado antigo) não quebra o parse', () {
      final json = barterJson()..remove('versionCode');
      final barter = BarterModel.fromJson(json);
      expect(barter.versionCode, isEmpty);
    });

    /// Antes, `BarterStatus.values.byName` LANÇAVA aqui — e como o parse
    /// acontece dentro de um `map` sobre a lista inteira, um único registro
    /// com status desconhecido derrubava TODAS as permutas da tela.
    test('status desconhecido não derruba o parse da lista', () {
      expect(
        () => [barterJson(status: 'cancelled'), barterJson()].map(BarterModel.fromJson).toList(),
        returnsNormally,
      );
      final barter = BarterModel.fromJson(barterJson(status: 'cancelled'));
      expect(barter.status, BarterStatus.pending);
      expect(barter.id, 'PRM-2026-001');
    });
  });

  group('BarterVersionModel', () {
    test('lê a versão vigente com a tabela de valores', () {
      final version = BarterVersionModel.fromJson(versionJson());
      expect(version.code, 'S2026.02');
      expect(version.grainName, 'Soja');
      expect(version.grainPrice, 148.5);
      expect(version.isOpen, isTrue);
      expect(version.priceOf('5')?.price, 115.0);
      expect(version.priceOf('5')?.margin, 25.0);
      // Insumo fora da tabela não é permutável nesta gestão.
      expect(version.priceOf('9'), isNull);
    });

    test('sem metas (resposta do consultor) a versão continua completa', () {
      final version = BarterVersionModel.fromJson(versionJson());
      expect(version.goals, isEmpty);
      expect(version.anyGoalMet, isFalse);
      expect(version.realizedSales, 0);
    });

    /// Mesma defesa do status da permuta: um tipo de meta que este app não
    /// conhece não pode derrubar a tela do lançamento inteira.
    test('meta de tipo desconhecido não quebra o parse', () {
      final version = BarterVersionModel.fromJson(versionJson(withGoals: true));
      expect(version.goals, hasLength(2));
      expect(version.goals[0].kind, GoalKind.sales);
      expect(version.goals[1].kind, GoalKind.sales); // desconhecida → leitura mais comum
      expect(version.anyGoalMet, isTrue);
      expect(version.realizedBarters, 1);
    });
  });

  group('SeasonModel', () {
    test('lê a safra com as versões dentro', () {
      final season = SeasonModel.fromJson({
        'id': 3,
        'code': 'S2026',
        'name': 'Soja 2026',
        'year': 2026,
        'grainId': 1,
        'grainName': 'Soja',
        'status': 'open',
        'openedAt': '2026-01-05T00:00:00.000Z',
        'versions': [versionJson()],
      });
      expect(season.isOpen, isTrue);
      expect(season.versions.single.code, 'S2026.02');
    });
  });

  group('ProductClassModel', () {
    test('lê a classe com a regra vigente', () {
      final productClass = ProductClassModel.fromJson({
        'id': 5,
        'slug': 'fertilizantes',
        'name': 'Fertilizantes',
        'ruleType': 'percentOfTotal',
        'ruleValue': 30,
      });
      expect(productClass.slug, 'fertilizantes');
      expect(productClass.ruleType, ClassRuleType.percentOfTotal);
      expect(productClass.hasRule, isTrue);
      expect(productClass.ruleLabelAdmin, contains('30%'));
    });

    test('regra desconhecida vira "sem exigência" em vez de exceção', () {
      final productClass = ProductClassModel.fromJson(
        {'id': 9, 'slug': 'biologicos', 'name': 'Biológicos', 'ruleType': 'porVolume', 'ruleValue': 5},
      );
      expect(productClass.ruleType, ClassRuleType.none);
      expect(productClass.hasRule, isFalse);
    });
  });

  /// O produto chega em DUAS formas, e o modelo precisa dar a mesma resposta
  /// nas duas: a listagem manda o resumo do histórico (a série cresce a cada
  /// versão publicada e não pode viajar a cada login), o detalhe manda a série.
  group('ProductModel', () {
    Map<String, dynamic> base() => {
          'id': 1,
          'name': 'Soja',
          'unit': 'saca 60kg',
          'type': 'grain',
          'currentPrice': 148.5,
          'requiredPerHa': 0,
        };

    test('a listagem traz o resumo: variação e contagem sem a série', () {
      final product = ProductModel.fromJson(
        {...base(), 'firstPrice': 142.0, 'priceHistoryCount': 7},
      );

      expect(product.priceHistory, isEmpty);
      expect(product.priceHistoryCount, 7);
      expect(product.hasFullHistory, isFalse);
      // (148,5 − 142) / 142 = 4,577...%
      expect(product.deltaPct, closeTo(4.577, 0.001));
    });

    test('o detalhe traz a série, e a variação dá o mesmo número', () {
      final product = ProductModel.fromJson({
        ...base(),
        'priceHistory': [
          {'price': 142.0, 'changedBy': 'Barter S2026.01', 'changedAt': '2026-01-10T12:00:00.000Z'},
          {'price': 148.5, 'changedBy': 'Barter S2026.02', 'changedAt': '2026-02-10T12:00:00.000Z'},
        ],
      });

      expect(product.priceHistory, hasLength(2));
      expect(product.priceHistoryCount, 2);
      expect(product.hasFullHistory, isTrue);
      // Sem `firstPrice` no JSON, o primeiro ponto da série responde por ele —
      // é o que mantém as duas formas dizendo a mesma coisa.
      expect(product.firstPrice, 142.0);
      expect(product.deltaPct, closeTo(4.577, 0.001));
    });

    test('produto sem histórico nenhum não inventa variação', () {
      final product = ProductModel.fromJson({...base(), 'priceHistoryCount': 0});

      expect(product.firstPrice, isNull);
      expect(product.deltaPct, 0);
      expect(product.hasFullHistory, isTrue);
    });
  });

  /// A senha de primeira entrada chega junto com o cadastro, numa resposta só,
  /// e é a única vez que ela existe em texto puro.
  group('ProvisionedConsultant', () {
    test('lê o cadastro e a senha provisória da mesma resposta', () {
      final provisioned = ProvisionedConsultant.fromJson({
        'id': 7,
        'fullName': 'Nova Consultora',
        'email': 'nova@agrobarter.com.br',
        'role': 'consultant',
        'branch': 'Filial 03',
        'createdAt': '2026-08-13T10:00:00.000Z',
        'initials': 'NC',
        'mustChangePassword': true,
        'provisionalPassword': 'K7NP-4TQX',
      });

      expect(provisioned.provisionalPassword, 'K7NP-4TQX');
      expect(provisioned.consultant.name, 'Nova Consultora');
      expect(provisioned.consultant.mustChangePassword, isTrue);
      expect(provisioned.consultant.role, UserRole.consultant);
    });
  });
}
