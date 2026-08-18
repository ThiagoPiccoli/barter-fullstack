import '../models/models.dart';
import '../services/api/api_client.dart';

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

  Future<SeasonModel> openSeason({
    required String grainId,
    required int year,
    String? name,
    String? letter,
  }) async {
    final data = await api.post('/seasons', body: {
      'grainId': int.parse(grainId),
      'year': year,
      if (name != null && name.isNotEmpty) 'name': name,
      if (letter != null && letter.isNotEmpty) 'letter': letter,
    });
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
    DateTime? endsAt,
    double? targetSales,
    double? targetSacks,
    int? targetBarters,
    String? note,
    bool carryOver = false,
  }) async {
    final data = await api.upload(
      '/seasons/$seasonCode/versions/import',
      filename: filename,
      bytes: bytes,
      fields: {
        'grainPrice': '$grainPrice',
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
        if (targetSales != null) 'targetSales': '$targetSales',
        if (targetSacks != null) 'targetSacks': '$targetSacks',
        if (targetBarters != null) 'targetBarters': '$targetBarters',
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
