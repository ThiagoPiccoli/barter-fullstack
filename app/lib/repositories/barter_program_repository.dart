import 'dart:convert';

import '../models/models.dart';
import '../services/api/api_client.dart';

/// O VENCIMENTO DA CPR como INSTANTE: meio-dia UTC do dia escolhido.
///
/// O vencimento é um DIA, e não um instante — mas ele viaja como data-hora, e o
/// aparelho oferece o que o calendário devolveu: meia-noite em hora LOCAL.
/// Meia-noite de Brasília vira 03:00 UTC, ainda o mesmo dia; meia-noite num fuso
/// a leste de Greenwich cai no dia ANTERIOR em UTC, e a cédula sairia vencendo
/// um dia antes do que o admin escolheu — num campo que ninguém mais confere
/// depois, dentro de um título executável. Meio-dia é o único horário que não
/// vira o dia em fuso nenhum.
DateTime cprDueDateInstant(DateTime day) => DateTime.utc(day.year, day.month, day.day, 12);

/// UMA CULTURA sendo lançada — o que o admin digita por grão ao publicar.
///
/// As quatro coisas que mudam de uma cultura para a outra viajam juntas porque
/// são decididas juntas: a cotação da saca converte o custo dos insumos em
/// sacas, a produtividade converte as sacas na área do penhor, o vencimento é a
/// data da entrega daquele grão e a meta mede o quanto já foi comprometido
/// nele.
class VersionGrainInput {
  final String grainId;
  final double price;
  final double estimatedYield;
  final DateTime? cprDueDate;
  final double? targetSacks;

  const VersionGrainInput({
    required this.grainId,
    required this.price,
    required this.estimatedYield,
    this.cprDueDate,
    this.targetSacks,
  });

  Map<String, dynamic> toJson() => {
        'grainId': int.parse(grainId),
        'price': price,
        'estimatedYield': estimatedYield,
        if (cprDueDate != null) 'cprDueDate': cprDueDateInstant(cprDueDate!).toIso8601String(),
        if (targetSacks != null) 'targetSacks': targetSacks,
      };
}

/// O LANÇAMENTO do Barter: safras, versões e a tabela de valores.
///
/// `current` é a única leitura que o consultor faz — é dela que a tela de nova
/// permuta descobre se há Barter aberto, quais CULTURAS ele aceita e por quanto
/// vale cada insumo. Todo o resto é do admin.
class BarterProgramRepository {
  /// A versão vigente, ou null quando não há Barter lançado.
  ///
  /// [grainId] escolhe a CULTURA pela qual a tabela vem convertida — o mesmo
  /// insumo custa 0,77 saca de soja e 1,78 de milho, e quem lê em sacas (o
  /// consultor) precisa da conversão da cultura que ele escolheu. Sem ele, a
  /// primeira cultura do lançamento.
  Future<BarterVersionModel?> current({String? grainId}) async =>
      parseVersion(await currentRaw(grainId: grainId));

  /// A mesma versão, ainda como veio da API. `null` aqui é resposta legítima do
  /// servidor — significa que NÃO HÁ Barter aberto —, e é diferente de nunca ter
  /// perguntado: quem distingue as duas é `AppData.lastSyncAt`.
  Future<Map<String, dynamic>?> currentRaw({String? grainId}) async =>
      await api.get(
        '/barter-versions/current${grainId == null ? '' : '?grainId=$grainId'}',
      ) as Map<String, dynamic>?;

  BarterVersionModel? parseVersion(Map<String, dynamic>? row) =>
      row == null ? null : BarterVersionModel.fromJson(row);

  Future<List<SeasonModel>> listSeasons() async {
    final data = await api.get('/seasons') as List;
    return data.cast<Map<String, dynamic>>().map(SeasonModel.fromJson).toList();
  }

  /// Detalhe de uma versão — é aqui que vêm as metas com o realizado.
  Future<BarterVersionModel> findVersion(String code) async {
    final data = await api.get('/barter-versions/$code');
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// ABRE A SAFRA — o CICLO, e não mais a cultura.
  ///
  /// Não há grão aqui: as culturas são do LANÇAMENTO (ver [VersionGrainInput]),
  /// porque elas coexistem e mudam de uma versão para a outra — o Barter pode
  /// abrir só com soja e acrescentar o milho na versão seguinte, sem que a safra
  /// tenha deixado de ser a mesma.
  Future<SeasonModel> openSeason({
    required int year,
    String? name,
    String? letter,
  }) async {
    final data = await api.post('/seasons', body: {
      'year': year,
      if (name != null && name.isNotEmpty) 'name': name,
      if (letter != null && letter.isNotEmpty) 'letter': letter,
    });
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  /// ACERTA UMA CULTURA de uma versão já publicada: a cotação da saca, a
  /// produtividade estimada, o vencimento da CPR ou a meta de sacas dela.
  ///
  /// Rota própria (`PUT`), e não um "editar versão": esses números nascem no
  /// lançamento, e mudar um deles no meio do Barter obrigaria a republicar a
  /// tabela inteira — o que encerraria a versão vigente e reiniciaria a contagem
  /// do realizado por causa de um campo. Mexer no vencimento muda a data de
  /// entrega de TODA cédula daquela cultura que ainda não foi emitida, e por
  /// isso o ato deixa rastro na trilha de auditoria.
  Future<BarterVersionModel> updateGrain(
    String versionCode,
    String grainId, {
    double? price,
    double? estimatedYield,
    DateTime? cprDueDate,
    double? targetSacks,
  }) async {
    final data = await api.put(
      '/barter-versions/$versionCode/grains/$grainId',
      // Só o que veio: um `PUT` que mandasse os quatro campos sempre
      // reescreveria com `null` o que esta tela não estava editando.
      body: {
        'price': ?price,
        'estimatedYield': ?estimatedYield,
        if (cprDueDate != null) 'cprDueDate': cprDueDateInstant(cprDueDate).toIso8601String(),
        'targetSacks': ?targetSacks,
      },
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  Future<SeasonModel> closeSeason(String code) async {
    final data = await api.post('/seasons/$code/close');
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  Future<BarterVersionModel> closeVersion(String code) async {
    final data = await api.post('/barter-versions/$code/close');
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// Troca o modo de encerramento por meta da versão vigente.
  ///
  /// A versão que volta pode vir ENCERRADA: ligar o automático com a meta já
  /// batida fecha o Barter na hora, e é o servidor quem decide isso. Por isso a
  /// resposta é usada como está, e não remendada com `closeOnGoal: true`.
  Future<BarterVersionModel> setCloseOnGoal(String code, bool enabled) async {
    final data = await api.put(
      '/barter-versions/$code/close-on-goal',
      body: {'enabled': enabled},
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// LIGA ou DESLIGA o seguro agrícola do Barter vigente.
  ///
  /// Existe pelo mesmo motivo do modo de encerramento: a opção nasce no
  /// lançamento, e mudar de ideia no meio do Barter (a apólice saiu depois da
  /// tabela, a diretoria decidiu incluir) não pode custar uma republicação —
  /// que encerraria a versão e reiniciaria a contagem do realizado.
  ///
  /// O que ela NÃO faz é mexer em permuta já registrada: a taxa está congelada
  /// em cada uma. Vale para as próximas.
  Future<BarterVersionModel> setInsurance(String code, bool enabled) async {
    final data = await api.put(
      '/barter-versions/$code/insurance',
      body: {'enabled': enabled},
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// Publica a próxima versão a partir da planilha do fornecedor.
  ///
  /// Os limites vão como TEXTO porque o corpo é multipart; o servidor aceita
  /// vírgula decimal (o mesmo leitor de número da planilha), então não é
  /// preciso reformatar o que o admin digitou.
  Future<BarterVersionModel> publishFromFile({
    required String seasonCode,
    required String filename,
    required List<int> bytes,
    required List<VersionGrainInput> grains,
    DateTime? endsAt,
    double? targetSales,
    int? targetBarters,
    bool closeOnGoal = false,
    bool insuranceRequired = false,
    String? note,
    bool carryOver = false,
  }) async {
    final data = await api.upload(
      '/seasons/$seasonCode/versions/import',
      filename: filename,
      bytes: bytes,
      fields: {
        // AS CULTURAS em JSON dentro de um campo de texto: no multipart todo
        // campo é texto, e uma lista de objetos não tem como chegar de outro
        // jeito. A META DE SACAS viaja aqui dentro, e não ao lado das outras
        // metas, porque ela é de cada cultura — sacas de soja e de milho não
        // somam.
        'grains': jsonEncode(grains.map((grain) => grain.toJson()).toList()),
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
        if (targetSales != null) 'targetSales': '$targetSales',
        if (targetBarters != null) 'targetBarters': '$targetBarters',
        // Só vai quando é `true`: o padrão do servidor é o manual, e mandar
        // "false" é dizer a mesma coisa com um campo a mais no multipart.
        if (closeOnGoal) 'closeOnGoal': 'true',
        // O SEGURO do lançamento, pela mesma regra do `closeOnGoal`: só viaja
        // quando é `true`, porque o padrão do servidor é o Barter sem seguro.
        if (insuranceRequired) 'insuranceRequired': 'true',
        if (note != null && note.isNotEmpty) 'note': note,
        if (carryOver) 'carryOver': 'true',
      },
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// Corrige um valor da versão vigente. O `productId` de uma das CULTURAS
  /// ajusta a cotação da saca dela — é o mesmo caminho, de propósito.
  Future<BarterVersionModel> updatePrice(
    String versionCode,
    String productId,
    double price,
  ) async {
    final data = await api.put(
      '/barter-versions/$versionCode/prices/$productId',
      body: {'price': price},
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }
}
