import '../models/models.dart';
import '../services/api/api_client.dart';

/// O QUE A CARGA DA PLANILHA DEVOLVEU: a base e o que foi lido dela.
///
/// [priceColumnHeader] é o título da coluna como ele estava no arquivo — e é o
/// campo mais importante daqui. A planilha da seguradora traz `SEM Subvenção`,
/// `COM Subvenção` e o `Reajuste para Safra`, que são três preços para o mesmo
/// hectare; ver o título escolhido é como o admin percebe, no mesmo minuto, que
/// a planilha deste ano veio com os títulos trocados.
class InsuranceImportResult {
  final List<InsuranceRateModel> rates;

  /// O nome curto da coluna ("reajuste para a safra") e o título dela no
  /// arquivo ("Reajuste para Safra (maio/26) + 1,5% financeiro").
  final String priceColumnLabel;
  final String priceColumnHeader;

  /// Quantas praças o arquivo trouxe, e quantas linhas de enfeite foram
  /// ignoradas — a "Selecione o Município", com tudo zerado.
  final int imported;
  final int ignored;

  const InsuranceImportResult({
    this.rates = const [],
    this.priceColumnLabel = '',
    this.priceColumnHeader = '',
    this.imported = 0,
    this.ignored = 0,
  });

  factory InsuranceImportResult.fromJson(Map<String, dynamic> json) {
    final column = (json['priceColumn'] as Map?)?.cast<String, dynamic>() ?? const {};
    return InsuranceImportResult(
      rates: ((json['rates'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(InsuranceRateModel.fromJson)
          .toList(),
      priceColumnLabel: (column['label'] ?? '') as String,
      priceColumnHeader: (column['header'] ?? '') as String,
      imported: (json['imported'] as num?)?.toInt() ?? 0,
      ignored: (json['ignored'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A BASE DE SEGUROS POR MUNICÍPIO — quanto custa segurar um hectare em cada
/// praça.
///
/// A LEITURA é de todo mundo, e de propósito: o consultor precisa saber quanto
/// o seguro vai custar ao cliente dele ANTES de fechar a permuta. Quem não vê
/// R$ recebe o valor convertido em sacas por hectare (ver
/// [InsuranceRateModel]), que é a moeda em que ele lê a permuta inteira.
///
/// A ESCRITA é do admin (`insurance.manage`), e o servidor recusa quem não a
/// tem — linha a linha ou pela planilha da seguradora.
///
/// Não é paginada, pelo mesmo critério das unidades e das classes: a lista tem
/// teto natural (uma empresa opera em dezenas de praças) e as telas precisam
/// dela inteira — é dela que saem a conferência do admin e a prévia do custo.
class InsuranceRepository {
  Future<List<InsuranceRateModel>> list() async => parse(await listRaw());

  Future<List<Map<String, dynamic>>> listRaw() async =>
      (await api.get('/insurance-rates') as List).cast<Map<String, dynamic>>();

  List<InsuranceRateModel> parse(List<Map<String, dynamic>> rows) =>
      rows.map(InsuranceRateModel.fromJson).toList();

  Future<InsuranceRateModel> create({
    required String city,
    required double valuePerHa,
    String? note,
  }) async {
    final data = await api.post(
      '/insurance-rates',
      body: _payload(city: city, valuePerHa: valuePerHa, note: note),
    );
    return InsuranceRateModel.fromJson(data as Map<String, dynamic>);
  }

  Future<InsuranceRateModel> update(
    String id, {
    required String city,
    required double valuePerHa,
    String? note,
  }) async {
    final data = await api.put(
      '/insurance-rates/$id',
      body: _payload(city: city, valuePerHa: valuePerHa, note: note),
    );
    return InsuranceRateModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => api.delete('/insurance-rates/$id');

  /// A CARGA DA PLANILHA — o caminho do admin quando a cotação chega com
  /// dezenas de praças.
  ///
  /// `replace` é a decisão do formulário, e é grande demais para um padrão
  /// silencioso: ligado, o que não está na planilha é APAGADO da base (é a
  /// tabela nova de safra — praça que saiu da lista é praça que a seguradora
  /// não cobre mais); desligado, a carga acrescenta e atualiza, e o que não
  /// veio no arquivo fica como estava.
  ///
  /// A resposta traz a BASE INTEIRA e o RELATÓRIO da leitura. A base inteira
  /// porque a tela que carregou é a mesma que lista o cadastro — e no modo
  /// substituição essa é a única resposta honesta, já que o que saiu da lista
  /// saiu. O relatório porque a carga DECIDIU algo em nome de quem a disparou:
  /// a planilha da seguradora traz três valores por hectare, e o leitor escolheu
  /// um. Quem decide precisa ver a escolha no mesmo minuto.
  Future<InsuranceImportResult> importSheet({
    required String filename,
    required List<int> bytes,
    bool replace = false,
    String? column,
  }) async {
    final data = await api.upload(
      '/insurance-rates/import',
      filename: filename,
      bytes: bytes,
      fields: {
        // Só vai quando é substituição: o padrão do servidor é o que não apaga
        // nada, e mandar "merge" seria dizer a mesma coisa com um campo a mais.
        if (replace) 'mode': 'replace',
        // Idem para a coluna: ausente, o leitor escolhe pela ordem de
        // preferência dele (o reajuste da safra primeiro).
        'column': ?column,
      },
    );
    return InsuranceImportResult.fromJson(data as Map<String, dynamic>);
  }

  Map<String, dynamic> _payload({
    required String city,
    required double valuePerHa,
    String? note,
  }) => {
    'city': city,
    'valuePerHa': valuePerHa,
    if (note != null && note.isNotEmpty) 'note': note,
  };
}
