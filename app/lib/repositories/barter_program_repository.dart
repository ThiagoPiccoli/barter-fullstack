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

/// O LANÇAMENTO do Barter: as safras das culturas, as versões de cada uma e a
/// tabela de valores.
///
/// `current` é a única leitura que o consultor faz — é dela que a tela de nova
/// permuta descobre quais CULTURAS têm Barter aberto e por quanto vale cada
/// insumo em cada uma. Todo o resto é do admin.
///
/// As rotas endereçam safra e versão pelo `slug` (`SOJA2627`, `SOJA2627.02`): a
/// barra do código que se lê (`SOJA26/27`) não cabe numa URL.
class BarterProgramRepository {
  /// As versões vigentes — uma por cultura aberta —, cada uma com a sua tabela
  /// já na lente de quem pergunta. Lista vazia é "não há Barter aberto".
  Future<List<BarterVersionModel>> current() async => parseVersions(await currentRaw());

  /// As mesmas versões, ainda como vieram da API — é o que o pacote offline
  /// guarda, para o parse ser um só.
  Future<List<Map<String, dynamic>>> currentRaw() async =>
      (await api.get('/barter-versions/current') as List? ?? const [])
          .cast<Map<String, dynamic>>();

  List<BarterVersionModel> parseVersions(List<Map<String, dynamic>>? rows) =>
      (rows ?? const []).map(BarterVersionModel.fromJson).toList();

  Future<List<SeasonModel>> listSeasons() async {
    final data = await api.get('/seasons') as List;
    return data.cast<Map<String, dynamic>>().map(SeasonModel.fromJson).toList();
  }

  /// Detalhe de uma versão — é aqui que vêm as metas com o realizado.
  Future<BarterVersionModel> findVersion(String slug) async {
    final data = await api.get('/barter-versions/$slug');
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// ABRE A SAFRA DE UMA CULTURA — "Soja 26/27", "Canola 2027".
  ///
  /// O ano final é o inicial (cultura anual) ou o seguinte (cultura que cruza o
  /// ano); quem confere é o servidor. [insurancePolicy] é o seguro PADRÃO da
  /// cultura, que vem preenchido ao publicar cada versão.
  Future<SeasonModel> openSeason({
    required String grainId,
    required int startYear,
    required int endYear,
    InsurancePolicy insurancePolicy = InsurancePolicy.none,
  }) async {
    final data = await api.post('/seasons', body: {
      'grainId': int.parse(grainId),
      'startYear': startYear,
      'endYear': endYear,
      'insurancePolicy': insurancePolicy.apiValue,
    });
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  /// ACERTA OS TERMOS DA CULTURA numa versão já publicada: a cotação da saca, a
  /// produtividade estimada, o vencimento da CPR ou a meta de sacas.
  ///
  /// Rota própria (`PUT`): esses números nascem no lançamento, e mudar um deles
  /// no meio do Barter obrigaria a republicar a tabela inteira. Mexer no
  /// vencimento muda a data de entrega de TODA cédula da versão que ainda não
  /// foi emitida, e por isso o ato deixa rastro na trilha de auditoria.
  Future<BarterVersionModel> updateTerms(
    String versionSlug, {
    double? grainPrice,
    double? estimatedYield,
    DateTime? cprDueDate,
    double? targetSacks,
  }) async {
    final data = await api.put(
      '/barter-versions/$versionSlug/terms',
      // Só o que veio: um `PUT` que mandasse os quatro campos sempre
      // reescreveria com `null` o que esta tela não estava editando.
      body: {
        'grainPrice': ?grainPrice,
        'estimatedYield': ?estimatedYield,
        if (cprDueDate != null) 'cprDueDate': cprDueDateInstant(cprDueDate).toIso8601String(),
        'targetSacks': ?targetSacks,
      },
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// ENCERRA a safra da cultura (e a versão vigente dela). As outras culturas
  /// seguem.
  Future<SeasonModel> closeSeason(String slug) async {
    final data = await api.post('/seasons/$slug/close');
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  /// REABRE a safra encerrada — versões novas voltam a poder sair nela.
  Future<SeasonModel> reopenSeason(String slug) async {
    final data = await api.post('/seasons/$slug/reopen');
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  /// O SEGURO PADRÃO da safra — o que vem preenchido na próxima versão.
  Future<SeasonModel> setSeasonInsurance(String slug, InsurancePolicy policy) async {
    final data = await api.put('/seasons/$slug/insurance', body: {'policy': policy.apiValue});
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  /// Encerra a versão: a cultura para de vender, e pode voltar com a próxima.
  Future<BarterVersionModel> closeVersion(String slug) async {
    final data = await api.post('/barter-versions/$slug/close');
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// Troca o modo de encerramento por meta da versão vigente.
  ///
  /// A versão que volta pode vir ENCERRADA: ligar o automático com a meta já
  /// batida fecha o Barter na hora, e é o servidor quem decide isso. Por isso a
  /// resposta é usada como está, e não remendada com `closeOnGoal: true`.
  Future<BarterVersionModel> setCloseOnGoal(String slug, bool enabled) async {
    final data = await api.put(
      '/barter-versions/$slug/close-on-goal',
      body: {'enabled': enabled},
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// A POLÍTICA DE SEGURO da versão vigente — obrigatório, opcional ou sem.
  ///
  /// O que ela NÃO faz é mexer em permuta já registrada: a escolha e a taxa
  /// estão congeladas em cada uma. Vale para as próximas.
  Future<BarterVersionModel> setInsurance(String slug, InsurancePolicy policy) async {
    final data = await api.put(
      '/barter-versions/$slug/insurance',
      body: {'policy': policy.apiValue},
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// Publica a próxima versão da safra a partir da PLANILHA DA CULTURA.
  ///
  /// Os campos vão como TEXTO porque o corpo é multipart; o servidor aceita
  /// vírgula decimal (o mesmo leitor de número da planilha), então não é
  /// preciso reformatar o que o admin digitou.
  Future<BarterVersionModel> publishFromFile({
    required String seasonSlug,
    required String filename,
    required List<int> bytes,
    required double grainPrice,
    required double estimatedYield,
    DateTime? cprDueDate,
    required InsurancePolicy insurancePolicy,
    DateTime? endsAt,
    double? targetSales,
    double? targetSacks,
    int? targetBarters,
    bool closeOnGoal = false,
    String? note,
    bool carryOver = false,
  }) async {
    final data = await api.upload(
      '/seasons/$seasonSlug/versions/import',
      filename: filename,
      bytes: bytes,
      fields: {
        'grainPrice': '$grainPrice',
        'estimatedYield': '$estimatedYield',
        if (cprDueDate != null) 'cprDueDate': cprDueDateInstant(cprDueDate).toIso8601String(),
        'insurancePolicy': insurancePolicy.apiValue,
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
        if (targetSales != null) 'targetSales': '$targetSales',
        if (targetSacks != null) 'targetSacks': '$targetSacks',
        if (targetBarters != null) 'targetBarters': '$targetBarters',
        // Só vai quando é `true`: o padrão do servidor é o manual, e mandar
        // "false" é dizer a mesma coisa com um campo a mais no multipart.
        if (closeOnGoal) 'closeOnGoal': 'true',
        if (note != null && note.isNotEmpty) 'note': note,
        if (carryOver) 'carryOver': 'true',
      },
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// Corrige um valor da versão vigente. O `productId` do GRÃO ajusta a cotação
  /// da saca — é o mesmo caminho, de propósito.
  Future<BarterVersionModel> updatePrice(
    String versionSlug,
    String productId,
    double price,
  ) async {
    final data = await api.put(
      '/barter-versions/$versionSlug/prices/$productId',
      body: {'price': price},
    );
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }
}
