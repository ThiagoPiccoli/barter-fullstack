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
        'unitId': 2,
        'unitName': 'Filial 02 – Gran. Santa T.',
        'status': status,
        'managerId': 7,
        'managerName': 'Beatriz Nogueira',
        'createdAt': '2026-01-10T00:00:00.000Z',
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
            'unit': 'saco 50kg',
            'quantity': 48,
            'unitValue': 115.0,
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
          },
        ],
        if (withGoals) ...{
          'realized': {'sales': 5520.0, 'sacks': 80.4, 'barters': 1},
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

    test('guarda a versão do Barter em que foi fechada', () {
      final barter = BarterModel.fromJson(barterJson(status: 'approved'));
      expect(barter.versionCode, 'S2026.02');
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

    /// A ETAPA DO GERENTE tem duas leituras diferentes no mesmo par de campos:
    /// `managerName` diz A QUEM a permuta foi enviada (vem preenchido desde a
    /// criação), e `managerNote` diz se ele já respondeu. Ler as duas como uma
    /// só faria toda permuta enviada parecer já pareceada.
    test('enviada ao gerente: destinatário preenchido, parecer ainda não', () {
      final barter = BarterModel.fromJson(barterJson(status: 'sentToManager'));

      expect(barter.status, BarterStatus.sentToManager);
      expect(barter.awaitsManager, isTrue);
      expect(barter.managerLabel, 'Beatriz Nogueira');
      // O destinatário existe; o parecer, não.
      expect(barter.hasManagerOpinion, isFalse);
      expect(barter.statusLabel, 'Enviada ao Gerente');
    });

    /// A tela só oferece o botão de parecer a quem o servidor deixaria dar —
    /// oferecer um botão que a API recusa é pior do que não mostrá-lo.
    test('a permuta só espera o parecer de quem ela foi endereçada', () {
      final barter = BarterModel.fromJson(barterJson(status: 'sentToManager'));

      expect(barter.awaitsOpinionFrom('7'), isTrue);
      expect(barter.awaitsOpinionFrom('10'), isFalse); // outro gerente
      expect(barter.awaitsOpinionFrom(null), isFalse); // não é gerente
      expect(barter.awaitsOpinionFrom(''), isFalse);
    });

    test('com o parecer escrito, a permuta já não espera o gerente', () {
      final json = barterJson(status: 'pending')
        ..['managerNote'] = 'Estoque conferido, volume compatível com a área.'
        ..['managerReviewedAt'] = '2026-01-11T10:00:00.000Z';
      final barter = BarterModel.fromJson(json);

      expect(barter.hasManagerOpinion, isTrue);
      expect(barter.awaitsManager, isFalse);
      expect(barter.awaitsOpinionFrom('7'), isFalse);
      expect(barter.managerReviewedAt, isNotNull);
    });

    /// A unidade é LOGÍSTICA. Permutas anteriores ao cadastro de unidades não
    /// têm local de retirada, e a tela precisa mostrar isso sem quebrar.
    test('permuta sem unidade (dado antigo) mostra travessão', () {
      final json = barterJson()
        ..remove('unitId')
        ..remove('unitName');
      final barter = BarterModel.fromJson(json);

      expect(barter.unitId, isEmpty);
      expect(barter.unitLabel, '—');
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

  /// A UNIDADE é um local, e o modelo dela é curto por isso. Se um dia este
  /// grupo ganhar um teste de "responsável pela unidade", é sinal de que o
  /// modelo mudou — quem analisa a permuta é o gerente do CONSULTOR.
  group('UnitModel', () {
    test('lê o local de retirada', () {
      final unit = UnitModel.fromJson({
        'id': 2,
        'name': 'Filial 02 – Gran. Santa T.',
        'city': 'Sarandi/PR',
        'createdAt': '2026-08-16T10:00:00.000Z',
        'initials': 'FG',
      });

      expect(unit.id, '2');
      expect(unit.label, 'Filial 02 – Gran. Santa T. • Sarandi/PR');
    });
  });

  group('UserModel', () {
    /// O gerente do consultor é o que decide para quem as permutas dele vão —
    /// e é a única forma de o app saber isso sem a lista de gerentes, que é
    /// rota de admin.
    test('o consultor traz o gerente dele; os outros papéis, não', () {
      final base = {
        'email': 'joao.silva@agrobarter.com.br',
        'createdAt': '2026-01-10T00:00:00.000Z',
        'initials': 'JS',
      };

      final consultor = UserModel.fromJson({
        ...base,
        'id': 2,
        'fullName': 'João Silva',
        'role': 'consultant',
        'unitId': 2,
        'branch': 'Filial 02 – Gran. Santa T.',
        'managerId': 7,
        'managerName': 'Beatriz Nogueira',
      });
      expect(consultor.managerId, '7');
      expect(consultor.managerName, 'Beatriz Nogueira');
      expect(consultor.unitId, '2');

      final gerente = UserModel.fromJson({
        ...base,
        'id': 7,
        'fullName': 'Beatriz Nogueira',
        'role': 'manager',
        'unitId': 1,
        'branch': 'Matriz',
        'managerId': null,
        'managerName': null,
      });
      expect(gerente.managerId, isEmpty);
      expect(gerente.managerName, isEmpty);
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
