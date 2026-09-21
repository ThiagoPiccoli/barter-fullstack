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

/// O LANÇAMENTO do Barter: safras, versões e a tabela de valores.
///
/// `current` é a única leitura que o consultor faz — é dela que a tela de nova
/// permuta descobre se há Barter aberto, qual é o grão e por quanto vale cada
/// insumo. Todo o resto é do admin.
class BarterProgramRepository {
  /// A versão vigente, ou null quando não há Barter lançado.
  Future<BarterVersionModel?> current() async => parseVersion(await currentRaw());

  /// A mesma versão, ainda como veio da API. `null` aqui é resposta legítima do
  /// servidor — significa que NÃO HÁ Barter aberto —, e é diferente de nunca ter
  /// perguntado: quem distingue as duas é `AppData.lastSyncAt`.
  Future<Map<String, dynamic>?> currentRaw() async =>
      await api.get('/barter-versions/current') as Map<String, dynamic>?;

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

  /// [cprDueDate] é o VENCIMENTO DA CPR desta safra — a data em que o produtor
  /// entrega o grão. Opcional aqui de propósito: ele é da colheita, e a safra
  /// abre antes de o calendário dela estar fechado. Sem ele a safra abre do
  /// mesmo jeito, e a pendência aparece na cédula endereçada ao admin.
  Future<SeasonModel> openSeason({
    required String grainId,
    required int year,
    String? name,
    String? letter,
    DateTime? cprDueDate,
  }) async {
    final data = await api.post('/seasons', body: {
      'grainId': int.parse(grainId),
      'year': year,
      if (name != null && name.isNotEmpty) 'name': name,
      if (letter != null && letter.isNotEmpty) 'letter': letter,
      if (cprDueDate != null) 'cprDueDate': cprDueDateInstant(cprDueDate).toIso8601String(),
    });
    return SeasonModel.fromJson(data as Map<String, dynamic>);
  }

  /// ACERTA o vencimento da CPR de uma safra JÁ ABERTA.
  ///
  /// Rota própria (`PUT`), e não um "editar safra": é o único campo dela que se
  /// corrige depois de aberta, e mexer nele muda a data de entrega de TODA
  /// cédula da safra que ainda não foi emitida — por isso ele deixa rastro na
  /// trilha de auditoria, sozinho.
  Future<SeasonModel> setCprDueDate(String code, DateTime dueDate) async {
    final data = await api.put(
      '/seasons/$code/cpr-due-date',
      body: {'cprDueDate': cprDueDateInstant(dueDate).toIso8601String()},
    );
    return SeasonModel.fromJson(data as Map<String, dynamic>);
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
    required double grainPrice,
    required double estimatedYield,
    DateTime? endsAt,
    double? targetSales,
    double? targetSacks,
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
        'grainPrice': '$grainPrice',
        // A PRODUTIVIDADE vai junto do preço da saca, e é obrigatória como ele:
        // sem ela a versão nasceria vigente e recusando toda permuta, porque o
        // penhor não teria como ser dimensionado.
        'estimatedYield': '$estimatedYield',
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
        if (targetSales != null) 'targetSales': '$targetSales',
        if (targetSacks != null) 'targetSacks': '$targetSacks',
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

  /// Corrige um valor da versão vigente. O `productId` do grão da safra ajusta
  /// o valor da saca — é o mesmo caminho, de propósito.
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
