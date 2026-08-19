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

    /// O imposto sai da alíquota GRAVADA na permuta, não do cadastro do produtor
    /// na hora de mostrar: a alíquota muda por lei, e o comprovante de uma
    /// permuta fechada não pode passar a mostrar outro número.
    test('Funrural/Senar incide sobre a entrega de grão, na alíquota registrada', () {
      final json = barterJson(status: 'approved')
        ..['taxRegime'] = 'comercializacao'
        ..['taxRate'] = 1.63;
      final barter = BarterModel.fromJson(json);

      expect(barter.hasTax, isTrue);
      expect(barter.taxRegime, TaxRegime.comercializacao);
      expect(barter.taxRateLabel, '1,63%');
      // Entrega: 80,4444 sacas × R$ 148,50 = R$ 11.946,00 → 1,63% = R$ 194,72.
      expect(barter.taxAmount, closeTo(194.72, 0.005));
      // A mesma alíquota sobre as sacas, para quem não vê R$.
      expect(barter.taxInSacks, closeTo(1.31, 0.005));
    });

    /// Fechar sobre a FOLHA não isenta a entrega: sobra o Senar, e é essa
    /// diferença que a permuta guarda.
    test('permuta fechada sobre a folha carrega a alíquota do Senar', () {
      final json = barterJson(status: 'approved')
        ..['taxRegime'] = 'folha'
        ..['taxRate'] = 0.2;
      final barter = BarterModel.fromJson(json);

      expect(barter.taxRegime, TaxRegime.folha);
      expect(barter.taxRateLabel, '0,20%');
      // 80,4444 sacas × R$ 148,50 = R$ 11.946,00 → 0,20% = R$ 23,89.
      expect(barter.taxAmount, closeTo(23.89, 0.005));
    });

    /// Permutas fechadas antes do campo não têm alíquota registrada. Inventar a
    /// de hoje para elas seria afirmar um imposto que ninguém aplicou — a linha
    /// não aparece, e é [hasTax] que as telas leem para isso.
    test('permuta sem alíquota (dado antigo) não mostra imposto', () {
      final barter = BarterModel.fromJson(barterJson());
      expect(barter.hasTax, isFalse);
      // O regime ausente cai no padrão legal, mas sem alíquota não há linha.
      expect(barter.taxRegime, TaxRegime.comercializacao);
      expect(barter.taxAmount, 0);
      expect(barter.taxInSacks, 0);
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
      expect(barter.statusLabel, 'No gerente');
      // COM QUEM ela está parada. Sem `waitingFor` no JSON (resposta antiga),
      // fica null e a tela simplesmente não diz — em vez de dizer errado.
      expect(barter.waitingFor, isNull);
    });

    /// A LINHA DE PRODUÇÃO inteira, lida do servidor.
    ///
    /// O que este teste prende é que o app não deduz o fluxo: o estado, o rótulo
    /// e COM QUEM a permuta está vêm da resposta. Foi assim que a decisão pôde
    /// sair do admin e ir para o comitê sem o app aprender nada novo.
    test('lê os postos da linha: comitê, faturamento e o rótulo do servidor', () {
      final noComite = BarterModel.fromJson(barterJson()
        ..['waitingFor'] = 'committee'
        ..['statusLabel'] = 'No comitê');
      expect(noComite.awaitsCommittee, isTrue);
      expect(noComite.waitingFor, UserRole.committee);
      expect(noComite.statusLabel, 'No comitê');
      expect(noComite.wasApproved, isFalse);

      final aFaturar = BarterModel.fromJson(barterJson(status: 'approved')
        ..['waitingFor'] = 'biller'
        ..['reviewedBy'] = 'Ricardo Alencar'
        ..['reviewNote'] = 'Aprovada pelo comitê.');
      expect(aFaturar.awaitsInvoice, isTrue);
      expect(aFaturar.waitingFor, UserRole.biller);
      expect(aFaturar.hasDecision, isTrue);
      expect(aFaturar.reviewNote, 'Aprovada pelo comitê.');
      expect(aFaturar.wasApproved, isTrue);

      final faturada = BarterModel.fromJson(barterJson(status: 'invoiced')
        ..['invoicedBy'] = 'Patrícia Lemos'
        ..['invoicedAt'] = '2026-01-12T10:15:00.000Z'
        ..['invoiceNote'] = 'NF 4471');
      expect(faturada.isInvoiced, isTrue);
      expect(faturada.awaitsInvoice, isFalse);
      // Fim de linha: ninguém está com ela.
      expect(faturada.waitingFor, isNull);
      expect(faturada.invoicedBy, 'Patrícia Lemos');
      expect(faturada.invoicedAt, isNotNull);
      // Faturar não desfaz a aprovação — ela continua contando nos painéis.
      expect(faturada.wasApproved, isTrue);
    });

    /// A LINHA DO TEMPO só vem no detalhe. Na listagem ela não vem, e a tela
    /// precisa distinguir "não veio nesta resposta" de "não tem passos".
    test('a linha do tempo vem do detalhe, com o autor de cada passo', () {
      expect(BarterModel.fromJson(barterJson()).hasHistory, isFalse);

      final barter = BarterModel.fromJson(barterJson(status: 'approved')
        ..['events'] = [
          {
            'action': 'register',
            'fromStatus': null,
            'toStatus': 'sentToManager',
            'actorName': 'João Silva',
            'actorRole': 'consultant',
            'actorRoleLabel': 'Consultor',
            'note': null,
            'at': '2026-01-10T09:30:00.000Z',
          },
          {
            'action': 'review',
            'fromStatus': 'pending',
            'toStatus': 'approved',
            'actorName': 'Ricardo Alencar',
            'actorRole': 'committee',
            'actorRoleLabel': 'Comitê',
            'note': 'Aprovada.',
            'at': '2026-01-11T14:00:00.000Z',
          },
        ]);

      expect(barter.hasHistory, isTrue);
      expect(barter.events.first.title, 'Registrada pelo consultor');
      expect(barter.events.first.fromStatus, isNull);
      expect(barter.events.first.actorRole, UserRole.consultant);
      expect(barter.events.last.title, 'Aprovada pelo comitê');
      expect(barter.events.last.note, 'Aprovada.');
    });

    /// Um ato de um servidor mais novo não pode sumir da história nem derrubar
    /// a tela: ele aparece como "Andamento", com quem fez e quando.
    test('passo desconhecido continua visível na linha do tempo', () {
      final barter = BarterModel.fromJson(barterJson()
        ..['events'] = [
          {
            'action': 'cancel',
            'fromStatus': 'approved',
            'toStatus': 'cancelada',
            'actorName': 'Alguém',
            'actorRole': 'diretor',
            'actorRoleLabel': 'Diretor',
            'at': '2026-02-01T10:00:00.000Z',
          },
        ]);

      expect(barter.events.single.title, 'Andamento');
      expect(barter.events.single.actorRoleLabel, 'Diretor');
      // Papel que este app não conhece não vira consultor por descuido.
      expect(barter.events.single.actorRole, isNull);
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

  /// A CARTEIRA do produtor é lista, e não um id: consultores dividem região e
  /// atendem o mesmo cliente. O parse é onde essa mudança de contrato chega ao
  /// app, e é aqui que ela precisa estar fixada.
  group('ProducerModel', () {
    Map<String, dynamic> producerJson({List<dynamic> consultantIds = const [2]}) => {
          'id': 3,
          'name': 'Joaquim Tavares',
          'consultantIds': consultantIds,
          'document': 'CNPJ 12.345.678/0001-90',
          'phone': '(44) 99800-1003',
          'farmName': 'Fazenda Santa Rita',
          'city': 'Mandaguari/PR',
          'areaHa': 320,
          'initials': 'JT',
          'createdAt': '2020-11-03T00:00:00.000Z',
        };

    test('o produtor compartilhado responde aos dois consultores', () {
      final producer = ProducerModel.fromJson(producerJson(consultantIds: [4, 2]));

      expect(producer.consultantIds, ['4', '2']);
      expect(producer.isAttendedBy('2'), isTrue);
      expect(producer.isAttendedBy('4'), isTrue);
      expect(producer.isAttendedBy('3'), isFalse);
      expect(producer.areaLabel, '320 ha');
    });

    /// Produtor que perdeu o último consultor (a conta foi excluída) espera
    /// realocação. A tela do admin precisa desenhá-lo; quebrar no parse levaria
    /// a lista inteira junto, que é exatamente o caso que ninguém testa.
    test('carteira vazia é um estado, não um erro', () {
      expect(ProducerModel.fromJson(producerJson(consultantIds: [])).consultantIds, isEmpty);
      final semCampo = producerJson()..remove('consultantIds');
      expect(ProducerModel.fromJson(semCampo).consultantIds, isEmpty);
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
