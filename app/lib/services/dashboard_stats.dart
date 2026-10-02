/// O QUE OS PAINÉIS CONTAM — as perguntas de leitura da operação, longe da tela
/// que as desenha.
///
/// Elas viviam dentro do `build()` de três painéis (admin, retaguarda e
/// consultor) e de mais cinco telas: quem conta como negócio fechado, quantas
/// sacas a empresa tem a receber, como as permutas se agrupam por grão, por
/// filial e por insumo, há quantos dias a fila mais velha espera. Eram ~48
/// `.where(...)`/`fold` espalhados, e cada um deles é uma **decisão de
/// domínio** — "faturada ainda conta como aprovada" é regra, não layout.
///
/// O custo disso não era o de hoje, era o do dia seguinte: refazer a tela
/// significava reescrever as regras junto, e nenhuma delas tinha teste que não
/// fosse de widget. Aqui elas são funções puras — recebem a lista de permutas e
/// devolvem números —, testáveis sem montar um pixel.
///
/// O QUE NÃO ESTÁ AQUI, de propósito: cor, ícone, rótulo e ordem de cartão. A
/// tela continua dona de como mostrar; estas funções respondem o que mostrar.
library;

import '../models/models.dart';

/// Uma fatia da operação: um rótulo e o quanto ele soma.
///
/// Serve para os três agrupamentos que os painéis desenham (por grão, por
/// filial, por insumo) porque os três são a mesma forma — nome e número, do
/// maior para o menor. Um tipo por agrupamento seria três cópias da mesma
/// classe com nomes diferentes.
class StatSlice {
  final String label;
  final double value;

  const StatSlice(this.label, this.value);
}

/// OS NÚMEROS DE UM PAINEL, calculados de uma vez sobre a mesma lista.
///
/// De uma vez porque eles se explicam juntos: "3 aprovadas" e "4.000 sacas a
/// receber" descrevem o MESMO recorte, e computá-los em lugares diferentes é
/// como os dois passam a discordar depois de alguém mexer num deles.
class BarterStats {
  /// Negócio FECHADO: aprovadas e faturadas. Faturar não desfaz a aprovação —
  /// a permuta continua devendo as sacas dela (ver `BarterModel.wasApproved`).
  final List<BarterModel> closed;

  /// A fila do comitê, da mais nova para a mais antiga — a mesma ordem de toda
  /// lista do sistema.
  final List<BarterModel> pending;

  /// O que ainda espera o parecer do gerente.
  final List<BarterModel> atManager;

  /// Rascunhos — registrados e ainda na mão de quem os montou.
  final List<BarterModel> drafts;

  final int toInvoice;
  final int invoiced;
  final int denied;

  /// Sacas que os produtores entregarão pelas permutas fechadas — o "a receber"
  /// da empresa, em saca, na colheita.
  final double sacksReceivable;

  /// Sacas ainda no comitê: o que entra se ele aprovar.
  final double pendingSacks;

  /// Os dois lados da conta, em R$: o que foi retirado e o que paga.
  final double inputsValue;
  final double grainValue;

  /// Produtores distintos com permuta fechada.
  final int activeProducers;

  const BarterStats({
    required this.closed,
    required this.pending,
    required this.atManager,
    required this.drafts,
    required this.toInvoice,
    required this.invoiced,
    required this.denied,
    required this.sacksReceivable,
    required this.pendingSacks,
    required this.inputsValue,
    required this.grainValue,
    required this.activeProducers,
  });

  int get closedCount => closed.length;
  int get pendingCount => pending.length;
  int get atManagerCount => atManager.length;

  /// Ticket médio em sacas por permuta fechada. Zero sem permuta nenhuma — e
  /// não uma divisão por zero.
  double get averageSacks => closed.isEmpty ? 0 : sacksReceivable / closed.length;
}

/// Os números de um painel a partir das permutas que ele enxerga.
///
/// A LISTA JÁ CHEGA ESCOPADA: quem decide o que cada papel vê é o servidor, e
/// esta função não filtra por pessoa — ela conta o que recebeu. Foi assim que o
/// painel do faturista deixou de mostrar "No comitê": o escopo mudou lá, e a
/// conta aqui continuou a mesma.
BarterStats statsOf(List<BarterModel> barters) {
  final closed = barters.where((b) => b.wasApproved).toList();
  final pending = barters.where((b) => b.status == BarterStatus.pending).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return BarterStats(
    closed: closed,
    pending: pending,
    atManager: barters.where((b) => b.awaitsManager).toList(),
    drafts: barters.where((b) => b.isDraft).toList(),
    toInvoice: barters.where((b) => b.awaitsInvoice).length,
    invoiced: barters.where((b) => b.isInvoiced).length,
    denied: barters.where((b) => b.status == BarterStatus.denied).length,
    sacksReceivable: sacksOf(closed),
    pendingSacks: sacksOf(pending),
    inputsValue: closed.fold(0.0, (sum, b) => sum + b.inputCost),
    grainValue: closed.fold(0.0, (sum, b) => sum + b.grainCredit),
    activeProducers: closed.map((b) => b.producerId).toSet().length,
  );
}

/// As sacas comprometidas por um conjunto de permutas.
double sacksOf(Iterable<BarterModel> barters) =>
    barters.fold(0.0, (sum, b) => sum + b.totalGrainQty);

/// SACAS POR CULTURA — soja, milho, trigo.
///
/// Elas não somam entre si (grãos diferentes, compradores e calendários
/// diferentes), e é por isso que o painel as mostra separadas. A permuta antiga
/// sem grão registrado cai em "sem grão" em vez de sumir da conta: o número
/// total continuaria maior que a soma das fatias, e ninguém saberia por quê.
List<StatSlice> sacksByGrain(Iterable<BarterModel> barters) {
  final byGrain = <String, double>{};
  for (final barter in barters) {
    final name = barter.referenceGrainName.isEmpty ? 'sem grão' : barter.referenceGrainName;
    byGrain[name] = (byGrain[name] ?? 0) + barter.totalGrainQty;
  }
  return _ranked(byGrain);
}

/// A SAFRA DA CULTURA de uma permuta, como os painéis a nomeiam: a safra
/// ("Soja 26/27"), ou o grão nas permutas anteriores às safras por cultura, ou
/// "sem safra" — para a permuta não sumir da conta.
String seasonLabelOf(BarterModel barter) => barter.seasonName.isNotEmpty
    ? barter.seasonName
    : (barter.referenceGrainName.isNotEmpty ? barter.referenceGrainName : 'sem safra');

/// SACAS POR SAFRA DA CULTURA — Soja 26/27, Milho 2027.
///
/// É a leitura que o encerramento por cultura pede: cada safra é um Barter à
/// parte, com a sua meta, e o admin olha o compromisso de cada uma separado.
List<StatSlice> sacksBySeason(Iterable<BarterModel> barters) {
  final bySeason = <String, double>{};
  for (final barter in barters) {
    final label = seasonLabelOf(barter);
    bySeason[label] = (bySeason[label] ?? 0) + barter.totalGrainQty;
  }
  return _ranked(bySeason);
}

/// OS NÚMEROS DE CADA SAFRA DA CULTURA — o painel por cultura.
///
/// Um [BarterStats] por safra, sobre o mesmo recorte que o painel geral usa:
/// "3 fechadas, 4.000 sacas a receber, 2 no comitê" lido cultura por cultura.
/// Da safra com mais sacas a receber para a com menos.
List<({String label, BarterStats stats})> statsBySeason(Iterable<BarterModel> barters) {
  final grouped = <String, List<BarterModel>>{};
  for (final barter in barters) {
    grouped.putIfAbsent(seasonLabelOf(barter), () => []).add(barter);
  }
  return [
    for (final entry in grouped.entries) (label: entry.key, stats: statsOf(entry.value)),
  ]..sort((a, b) => b.stats.sacksReceivable.compareTo(a.stats.sacksReceivable));
}

/// As SAFRAS presentes nestas permutas — o seletor do filtro por cultura. Sai
/// das permutas, e não do cadastro de safras (que é do admin), pelo mesmo
/// motivo de [consultantsOf]. Permutas sem safra não viram opção.
List<({String id, String name})> seasonsOf(Iterable<BarterModel> barters) {
  final names = <String, String>{};
  for (final barter in barters) {
    if (barter.seasonId.isEmpty) continue;
    names[barter.seasonId] = barter.seasonName;
  }
  return names.entries.map((e) => (id: e.key, name: e.value)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// As permutas de UMA safra da cultura.
List<BarterModel> ofSeason(Iterable<BarterModel> barters, String seasonId) =>
    barters.where((b) => b.seasonId == seasonId).toList();

/// Sacas por FILIAL do consultor que registrou — o volume por praça.
List<StatSlice> sacksByBranch(Iterable<BarterModel> barters) {
  final byBranch = <String, double>{};
  for (final barter in barters) {
    byBranch[barter.consultantBranch] = (byBranch[barter.consultantBranch] ?? 0) +
        barter.totalGrainQty;
  }
  return _ranked(byBranch);
}

/// OS INSUMOS MAIS RETIRADOS (R$) — o lado insumo da história, que origina o
/// custo e, por consequência, as sacas.
///
/// [take] é do chamador porque é decisão de tela quantas linhas cabem; a ordem
/// é sempre a mesma, do maior para o menor.
List<StatSlice> topInputs(Iterable<BarterModel> barters, {int take = 5}) {
  final byInput = <String, double>{};
  for (final barter in barters) {
    for (final item in barter.inputs) {
      byInput[item.productName] = (byInput[item.productName] ?? 0) + item.total;
    }
  }
  return _ranked(byInput).take(take).toList();
}

/// AS PERMUTAS AGRUPADAS POR GERENTE, da fila mais velha para a mais nova.
///
/// A ordem é conteúdo: por nome, a linha que interessa ler — quem está segurando
/// há mais tempo — apareceria no meio da lista por acaso do alfabeto.
List<MapEntry<String, List<BarterModel>>> byManagerOldestFirst(
  Iterable<BarterModel> barters, {
  DateTime? now,
}) {
  final grouped = <String, List<BarterModel>>{};
  for (final barter in barters) {
    grouped.putIfAbsent(barter.managerLabel, () => []).add(barter);
  }
  final entries = grouped.entries.toList()
    ..sort((a, b) => waitingDays(b.value, now: now).compareTo(waitingDays(a.value, now: now)));
  return entries;
}

/// HÁ QUANTOS DIAS a mais antiga de um grupo espera.
///
/// A conta é sobre a CRIAÇÃO porque a permuta chega ao gerente no instante em
/// que nasce: entre registrar e o parecer não há outra etapa que segure o
/// relógio. [now] é parâmetro para o teste não depender do dia em que roda.
int waitingDays(Iterable<BarterModel> barters, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  return barters
      .map((b) => reference.difference(b.createdAt).inDays)
      .fold(0, (a, b) => a > b ? a : b);
}

/// OS RECORTES POR SUJEITO — as permutas de um consultor, de um produtor, de
/// uma unidade de retirada.
///
/// Eles são o "de quem é esta tela": o perfil do produtor mostra as dele, o do
/// consultor as dele. Estão aqui, e não soltos em cada tela, porque o critério
/// é do domínio — "permuta do consultor" é a que ELE registrou, e não a do time
/// dele nem a do produtor que ele divide com um colega.
List<BarterModel> ofConsultant(Iterable<BarterModel> barters, String consultantId) =>
    barters.where((b) => b.consultantId == consultantId).toList();

List<BarterModel> ofProducer(Iterable<BarterModel> barters, String producerId) =>
    barters.where((b) => b.producerId == producerId).toList();

List<BarterModel> ofUnit(Iterable<BarterModel> barters, String unitId) =>
    barters.where((b) => b.unitId == unitId).toList();

/// QUEM REGISTROU estas permutas — um por consultor, em ordem de nome.
///
/// É a lista do seletor de consultor na tela do gerente, e ela sai das
/// PERMUTAS, não do cadastro, por dois motivos. O gerente não lê o cadastro de
/// consultores (`/consultants` é do admin). E o que ele enxerga é o que foi
/// ENDEREÇADO a ele (`managerId` da permuta, gravado no envio): o consultor que
/// mudou de time continua com as permutas antigas na mesa deste gerente, e um
/// seletor montado pelo time de hoje não teria como chegar nelas.
///
/// O nome vem do snapshot da permuta. Se o mesmo consultor aparece com nomes
/// diferentes (o cadastro mudou entre uma permuta e outra), vale o da mais
/// recente.
List<({String id, String name})> consultantsOf(Iterable<BarterModel> barters) {
  final latest = <String, BarterModel>{};
  for (final b in barters) {
    final seen = latest[b.consultantId];
    if (seen == null || b.createdAt.isAfter(seen.createdAt)) latest[b.consultantId] = b;
  }
  return latest.values.map((b) => (id: b.consultantId, name: b.consultantName)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// O TRABALHO JÁ FEITO POR UMA PESSOA — o que o cadastro dela mostra ao lado do
/// nome, e o que a exclusão precisa avisar que fica órfão.
///
/// Cada posto deixa uma marca diferente na permuta, e é por ela que se conta: o
/// gerente é o DESTINATÁRIO (`managerId`), o faturista e o emissor ficam
/// assinados em texto (`invoicedBy`, `cprEmittedBy`) — snapshot que sobrevive à
/// exclusão da conta, que é justamente o caso em que alguém vai querer contar.
int opinionsOf(Iterable<BarterModel> barters, String managerId) =>
    barters.where((b) => b.managerId == managerId).length;

int invoicedBy(Iterable<BarterModel> barters, String name) =>
    barters.where((b) => b.invoicedBy == name).length;

int issuedBy(Iterable<BarterModel> barters, String name) =>
    barters.where((b) => b.cprEmittedBy == name).length;

/// Quantas permutas já foram DECIDIDAS — o trabalho do comitê, que é um órgão e
/// não uma pessoa: não há nome para contar, há decisão.
int decidedCount(Iterable<BarterModel> barters) => barters.where((b) => b.hasDecision).length;

/// Do maior para o menor — a ordem em que um ranking se lê.
List<StatSlice> _ranked(Map<String, double> totals) {
  final slices = totals.entries.map((e) => StatSlice(e.key, e.value)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return slices;
}
