import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/models/models.dart';
import 'package:agrobarter_app/services/dashboard_stats.dart';

/// O QUE OS PAINÉIS CONTAM, sem montar um pixel.
///
/// Estas regras viviam dentro do `build()` de três telas, e a única maneira de
/// testá-las era através do widget — o que significava, na prática, que elas não
/// eram testadas. Cada caso aqui é uma decisão de domínio que já custou
/// discussão: "faturada ainda conta como aprovada", "sacas de grãos diferentes
/// não somam", "a fila se lê da mais antiga para a mais nova".
void main() {
  BarterItem grain(String name, double qty) => BarterItem(
        productId: '1',
        productName: name,
        unit: 'saca 60kg',
        quantity: qty,
        unitValue: 100,
      );

  BarterItem input(String name, double qty, double value) => BarterItem(
        productId: '5',
        productName: name,
        unit: 'saco 50kg',
        quantity: qty,
        unitValue: value,
      );

  BarterModel barter({
    required String id,
    required BarterStatus status,
    String producerId = '10',
    String branch = 'Filial 02',
    String seasonId = '',
    String seasonName = '',
    String grainName = 'Soja',
    double sacks = 100,
    double inputValue = 100,
    DateTime? createdAt,
    String managerName = 'Beatriz Nogueira',
  }) => BarterModel(
        id: id,
        consultantId: '2',
        consultantName: 'João Silva',
        consultantBranch: branch,
        producerId: producerId,
        producerName: 'Antônio Carvalho',
        status: status,
        createdAt: createdAt ?? DateTime(2026, 3, 1),
        managerName: managerName,
        seasonId: seasonId,
        seasonName: seasonName,
        grains: [grain(grainName, sacks)],
        inputs: [input('NPK', 10, inputValue)],
      );

  group('statsOf', () {
    /// FATURAR NÃO DESFAZ A APROVAÇÃO: a permuta continua devendo as sacas
    /// dela. Enquanto a conta olhava um estado só, o negócio mais consolidado
    /// que existe sumia do painel no dia em que a nota era emitida.
    test('negócio fechado inclui aprovada e faturada', () {
      final stats = statsOf([
        barter(id: 'A', status: BarterStatus.approved),
        barter(id: 'B', status: BarterStatus.invoiced),
        barter(id: 'C', status: BarterStatus.pending),
        barter(id: 'D', status: BarterStatus.denied),
      ]);

      expect(stats.closedCount, 2);
      expect(stats.sacksReceivable, 200);
      expect(stats.pendingCount, 1);
      expect(stats.pendingSacks, 100);
      expect(stats.denied, 1);
    });

    /// A FILA DO COMITÊ se lê da mais nova para a mais antiga, como toda lista
    /// do sistema — e não na ordem em que a lista chegou.
    test('a fila do comitê vem da mais nova para a mais antiga', () {
      final stats = statsOf([
        barter(id: 'velha', status: BarterStatus.pending, createdAt: DateTime(2026, 1, 1)),
        barter(id: 'nova', status: BarterStatus.pending, createdAt: DateTime(2026, 5, 1)),
      ]);

      expect(stats.pending.map((b) => b.id), ['nova', 'velha']);
    });

    test('produtores ativos conta cada cliente uma vez', () {
      final stats = statsOf([
        barter(id: 'A', status: BarterStatus.approved, producerId: '10'),
        barter(id: 'B', status: BarterStatus.approved, producerId: '10'),
        barter(id: 'C', status: BarterStatus.approved, producerId: '11'),
      ]);

      expect(stats.activeProducers, 2);
    });

    /// TICKET MÉDIO sem permuta nenhuma é zero, e não uma divisão por zero.
    test('sem permuta fechada, o ticket médio é zero', () {
      expect(statsOf(const []).averageSacks, 0);
      expect(statsOf([barter(id: 'A', status: BarterStatus.pending)]).averageSacks, 0);
    });
  });

  /// CADA SAFRA DA CULTURA É UM BARTER À PARTE, e o painel a lê separada: a
  /// Soja 25/26 e a Soja 26/27 são compromissos de anos diferentes, mesmo sendo
  /// o mesmo grão.
  group('por safra da cultura', () {
    final permutas = [
      barter(id: 'A', status: BarterStatus.approved, seasonId: '3', seasonName: 'Soja 26/27', sacks: 100),
      barter(id: 'B', status: BarterStatus.approved, seasonId: '1', seasonName: 'Soja 25/26', sacks: 300),
      barter(id: 'C', status: BarterStatus.pending, seasonId: '3', seasonName: 'Soja 26/27', sacks: 50),
      barter(id: 'D', status: BarterStatus.approved, seasonId: '4', seasonName: 'Milho 2027', sacks: 70),
    ];

    test('as sacas se agrupam por safra, e não só por grão', () {
      final fatias = sacksBySeason(permutas.where((b) => b.wasApproved));
      expect(fatias.map((f) => f.label), ['Soja 25/26', 'Soja 26/27', 'Milho 2027']);
      expect(fatias.map((f) => f.value), [300, 100, 70]);
    });

    test('cada safra tem os seus números', () {
      final porSafra = statsBySeason(permutas);
      final soja2627 = porSafra.firstWhere((e) => e.label == 'Soja 26/27').stats;
      expect(soja2627.closedCount, 1);
      expect(soja2627.pendingCount, 1);
      expect(soja2627.sacksReceivable, 100);
    });

    test('o filtro lista as safras presentes e recorta por uma delas', () {
      expect(seasonsOf(permutas).map((s) => s.name), ['Milho 2027', 'Soja 25/26', 'Soja 26/27']);
      expect(ofSeason(permutas, '3').map((b) => b.id), ['A', 'C']);
    });

    /// A PERMUTA ANTERIOR ÀS SAFRAS POR CULTURA cai no grão dela, e não some.
    test('permuta sem safra cai no grão', () {
      expect(seasonLabelOf(barter(id: 'X', status: BarterStatus.approved)), 'Soja');
      expect(seasonsOf([barter(id: 'X', status: BarterStatus.approved)]), isEmpty);
    });
  });

  /// SACAS DE GRÃOS DIFERENTES NÃO SOMAM — são compromissos de entrega com
  /// compradores e calendários diferentes, e é por isso que o painel as separa.
  test('as sacas se agrupam por cultura, da maior para a menor', () {
    final fatias = sacksByGrain([
      barter(id: 'A', status: BarterStatus.approved, grainName: 'Soja', sacks: 100),
      barter(id: 'B', status: BarterStatus.approved, grainName: 'Milho', sacks: 300),
      barter(id: 'C', status: BarterStatus.approved, grainName: 'Soja', sacks: 50),
    ]);

    expect(fatias.map((f) => f.label), ['Milho', 'Soja']);
    expect(fatias.first.value, 300);
    expect(fatias.last.value, 150);
  });

  /// A PERMUTA ANTIGA SEM GRÃO cai em "sem grão" em vez de sumir: o total
  /// continuaria maior que a soma das fatias, e ninguém saberia por quê.
  test('permuta sem grão registrado não some da conta', () {
    final fatias = sacksByGrain([
      BarterModel(
        id: 'velha',
        consultantId: '2',
        consultantName: 'João Silva',
        consultantBranch: 'Filial 02',
        producerId: '10',
        producerName: 'Antônio Carvalho',
        status: BarterStatus.approved,
        createdAt: DateTime(2025, 1, 1),
        grains: const [],
        inputs: const [],
      ),
    ]);

    expect(fatias.single.label, 'sem grão');
  });

  test('o ranking de insumos soma por produto e corta no topo', () {
    final fatias = topInputs([
      barter(id: 'A', status: BarterStatus.approved, inputValue: 100),
      barter(id: 'B', status: BarterStatus.approved, inputValue: 250),
    ], take: 1);

    expect(fatias.single.label, 'NPK');
    // 10 × 100 + 10 × 250.
    expect(fatias.single.value, 3500);
  });

  test('o volume se agrupa por filial do consultor', () {
    final fatias = sacksByBranch([
      barter(id: 'A', status: BarterStatus.approved, branch: 'Filial 02', sacks: 100),
      barter(id: 'B', status: BarterStatus.approved, branch: 'Filial 34', sacks: 400),
    ]);

    expect(fatias.map((f) => f.label), ['Filial 34', 'Filial 02']);
  });

  group('a espera da fila do gerente', () {
    final hoje = DateTime(2026, 3, 20);

    /// A CONTA É SOBRE A CRIAÇÃO: a permuta chega ao gerente no instante em que
    /// nasce, e entre registrar e o parecer não há etapa que segure o relógio.
    test('conta os dias da mais antiga do grupo', () {
      final dias = waitingDays([
        barter(id: 'A', status: BarterStatus.sentToManager, createdAt: DateTime(2026, 3, 18)),
        barter(id: 'B', status: BarterStatus.sentToManager, createdAt: DateTime(2026, 3, 6)),
      ], now: hoje);

      expect(dias, 14);
    });

    /// QUEM SEGURA HÁ MAIS TEMPO PRIMEIRO: a ordem alfabética esconderia a
    /// linha que se quer ler.
    test('os gerentes vêm da fila mais velha para a mais nova', () {
      final grupos = byManagerOldestFirst([
        barter(
          id: 'A',
          status: BarterStatus.sentToManager,
          managerName: 'Ana',
          createdAt: DateTime(2026, 3, 19),
        ),
        barter(
          id: 'B',
          status: BarterStatus.sentToManager,
          managerName: 'Zeca',
          createdAt: DateTime(2026, 2, 1),
        ),
      ], now: hoje);

      expect(grupos.map((g) => g.key), ['Zeca', 'Ana']);
    });
  });

  /// O INVESTIMENTO MÉDIO NÃO REFAZ A CONTA DO SERVIDOR: é a média dos números
  /// de cada permuta ponderada pela área, que é o mesmo Σ sacas ÷ Σ área.
  group('área e investimento médio', () {
    BarterModel medida(String id, {required double sacks, required double area, bool comRegua = true}) =>
        BarterModel(
          id: id,
          consultantId: '2',
          consultantName: 'João Silva',
          consultantBranch: 'Filial 02',
          producerId: '10',
          producerName: 'Antônio Carvalho',
          status: BarterStatus.approved,
          createdAt: DateTime(2026, 3, 1),
          plantedAreaHa: area,
          // O que o serializer manda: sacas ÷ área, ou nada para quem não lê a
          // régua, ou null sem área.
          sacksPerHa: !comRegua || area <= 0 ? null : sacks / area,
          grains: [grain('Soja', sacks)],
          inputs: const [],
        );

    test('a média ponderada pela área é Σ sacas ÷ Σ área', () {
      final permutas = [medida('A', sacks: 1000, area: 100), medida('B', sacks: 300, area: 100)];
      // Média simples dos sc/ha daria (10 + 3) ÷ 2 = 6,5; a da lavoura é 6,5
      // aqui só por coincidência de áreas iguais — o caso abaixo separa as duas.
      expect(investmentPerHaOf(permutas), closeTo(1300 / 200, 1e-9));

      final desiguais = [medida('A', sacks: 1000, area: 100), medida('B', sacks: 300, area: 300)];
      expect(investmentPerHaOf(desiguais), closeTo(1300 / 400, 1e-9));
      expect(areaOf(desiguais), 400);
    });

    /// A permuta sem área não entra na média — nem as sacas dela, que
    /// inflariam o número sem hectare nenhum por baixo.
    test('a permuta sem área fica fora da média', () {
      final permutas = [medida('A', sacks: 1000, area: 100), medida('velha', sacks: 5000, area: 0)];
      expect(investmentPerHaOf(permutas), 10);
    });

    /// Sem a régua (quem não a recebe do servidor), o número some — e não vira
    /// zero.
    test('sem a régua do servidor, não há média', () {
      expect(investmentPerHaOf([medida('A', sacks: 1000, area: 100, comRegua: false)]), isNull);
      expect(investmentPerHaOf(const []), isNull);
    });

    test('o painel mede a área e o investimento das fechadas', () {
      final stats = statsOf([
        medida('A', sacks: 1000, area: 100),
        barter(id: 'B', status: BarterStatus.pending),
      ]);
      expect(stats.area, 100);
      expect(stats.investmentPerHa, 10);
    });
  });

  group('fases', () {
    /// A cédula emitida e a assinada ainda são permuta faturada: o painel não
    /// pode perdê-las da conta no dia em que o emissor age.
    test('agrupam os estados, e a cédula em andamento continua faturada', () {
      final fases = phaseCounts([
        barter(id: 'A', status: BarterStatus.approved),
        barter(id: 'B', status: BarterStatus.approvedWithConditions),
        barter(id: 'C', status: BarterStatus.invoiced),
        barter(id: 'D', status: BarterStatus.cprIssued),
        barter(id: 'E', status: BarterStatus.cprSigned),
        barter(id: 'F', status: BarterStatus.cprRegistered),
        barter(id: 'G', status: BarterStatus.awaitingPolicyWithConditions),
      ]);
      expect(fases[BarterPhase.toInvoice], 2);
      expect(fases[BarterPhase.invoiced], 3);
      expect(fases[BarterPhase.registered], 1);
      expect(fases[BarterPhase.atInsurer], 1);
      // Todas as fases vêm, inclusive as vazias.
      expect(fases.keys, BarterPhase.values);
      expect(fases[BarterPhase.denied], 0);
    });
  });

  group('tempo nas etapas', () {
    BarterModel andamento(String id, {
      required BarterStatus status,
      DateTime? sent,
      DateTime? opinion,
      DateTime? decided,
      String? reviewedBy,
    }) =>
        BarterModel(
          id: id,
          consultantId: '2',
          consultantName: 'João Silva',
          consultantBranch: 'Filial 02',
          producerId: '10',
          producerName: 'Antônio Carvalho',
          status: status,
          createdAt: DateTime(2026, 3, 1),
          consultantSentAt: sent,
          managerReviewedAt: opinion,
          updatedAt: decided,
          reviewedBy: reviewedBy,
          grains: const [],
          inputs: const [],
        );

    /// O parecer conta do ENCAMINHAMENTO: o rascunho que o consultor segurou
    /// não é espera do gerente.
    test('cada etapa mede da chegada à saída', () {
      final permutas = [
        andamento('A',
            status: BarterStatus.approved,
            sent: DateTime(2026, 3, 3),
            opinion: DateTime(2026, 3, 5),
            decided: DateTime(2026, 3, 11),
            reviewedBy: 'Comitê'),
        andamento('B',
            status: BarterStatus.pending, sent: DateTime(2026, 3, 1), opinion: DateTime(2026, 3, 5)),
      ];
      expect(averageStageDays(permutas, BarterStage.assembly), 1); // (2 + 0) ÷ 2
      expect(averageStageDays(permutas, BarterStage.opinion), 3); // (2 + 4) ÷ 2
      // B ainda está no comitê: o relógio dela não parou, e ela não entra.
      expect(averageStageDays(permutas, BarterStage.decision), 6);
      expect(averageStageDays(permutas, BarterStage.policy), isNull);
    });

    test('a espera em curso conta da chegada à etapa atual', () {
      final noComite = andamento('B',
          status: BarterStatus.pending, sent: DateTime(2026, 3, 1), opinion: DateTime(2026, 3, 5));
      expect(currentStageOf(noComite), BarterStage.decision);
      expect(daysWaiting(noComite, now: DateTime(2026, 3, 12)), 7);
      expect(daysWaiting(barter(id: 'X', status: BarterStatus.denied)), 0);
    });
  });

  group('por consultor', () {
    test('cada consultor tem os próprios números', () {
      BarterModel de(String id, String consultantId, String name, BarterStatus status) => BarterModel(
            id: id,
            consultantId: consultantId,
            consultantName: name,
            consultantBranch: 'Filial 02',
            producerId: '10',
            producerName: 'Antônio Carvalho',
            status: status,
            createdAt: DateTime(2026, 3, 1),
            grains: [grain('Soja', 100)],
            inputs: const [],
          );
      final linhas = analysisByConsultant([
        de('A', '2', 'João Silva', BarterStatus.approved),
        de('B', '2', 'João Silva', BarterStatus.pending),
        de('C', '3', 'Ana Souza', BarterStatus.approved),
      ]);
      expect(linhas.map((l) => l.name), ['Ana Souza', 'João Silva']);
      final joao = linhas.last;
      expect(joao.barters.length, 2);
      expect(joao.stats.sacksReceivable, 100);
      expect(joao.phases[BarterPhase.atCommittee], 1);
    });
  });

  group('seguradora e emissor', () {
    /// A área segurada é a da LINHA DO SEGURO, e só das que já têm apólice.
    test('a área segurada se agrupa por cultura, só com apólice', () {
      BarterModel segurada(String id, String grainName, double area, {String? policy}) => BarterModel(
            id: id,
            consultantId: '2',
            consultantName: 'João Silva',
            consultantBranch: 'Filial 02',
            producerId: '10',
            producerName: 'Antônio Carvalho',
            status: BarterStatus.approved,
            createdAt: DateTime(2026, 3, 1),
            plantedAreaHa: 999,
            insurancePolicyNumber: policy,
            grains: [grain(grainName, 100)],
            inputs: [
              BarterItem(
                productId: '9',
                productName: 'Seguro agrícola',
                unit: 'ha',
                quantity: area,
                unitValue: 50,
                insurance: true,
              ),
            ],
          );
      final fatias = insuredAreaByGrain([
        segurada('A', 'Soja', 100, policy: 'AP-1'),
        segurada('B', 'Milho', 300, policy: 'AP-2'),
        segurada('C', 'Soja', 50, policy: 'AP-3'),
        segurada('D', 'Soja', 1000),
      ]);
      expect(fatias.map((f) => f.label), ['Milho', 'Soja']);
      expect(fatias.map((f) => f.value), [300, 150]);
    });

    test('as cédulas em aberto se agrupam por safra', () {
      final grupos = openCprsBySeason([
        barter(id: 'A', status: BarterStatus.invoiced, seasonId: '3', seasonName: 'Soja 26/27'),
        barter(id: 'B', status: BarterStatus.cprSigned, seasonId: '3', seasonName: 'Soja 26/27'),
        barter(id: 'C', status: BarterStatus.cprIssued, seasonId: '4', seasonName: 'Milho 2027'),
        barter(id: 'D', status: BarterStatus.cprRegistered, seasonId: '4', seasonName: 'Milho 2027'),
      ]);
      expect(grupos.map((g) => g.label), ['Soja 26/27', 'Milho 2027']);
      expect(grupos.first.barters.length, 2);
      expect(grupos.last.barters.single.id, 'C');
    });
  });
}
