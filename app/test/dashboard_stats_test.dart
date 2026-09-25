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

    /// A FILA DO COMITÊ se lê da mais antiga para a mais nova: é a ordem de
    /// "ação necessária", e a alfabética esconderia quem espera há mais tempo.
    test('a fila do comitê vem da mais antiga para a mais nova', () {
      final stats = statsOf([
        barter(id: 'nova', status: BarterStatus.pending, createdAt: DateTime(2026, 5, 1)),
        barter(id: 'velha', status: BarterStatus.pending, createdAt: DateTime(2026, 1, 1)),
      ]);

      expect(stats.pending.map((b) => b.id), ['velha', 'nova']);
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
}
