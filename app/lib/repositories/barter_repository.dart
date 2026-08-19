import '../models/models.dart';
import '../services/api/api_client.dart';

/// Permutas. O payload de criação leva apenas produtos e quantidades — quem
/// precifica, valida mínimos e calcula as sacas do grão é o servidor.
///
/// Nem o grão vai no payload: ele é o da safra, e a versão vigente do Barter é
/// quem diz por quanto vale a saca.
class BarterRepository {
  /// Todas as permutas visíveis para o usuário. A rota é paginada no servidor
  /// (ver ApiClient.getAll): o cache do app continua completo, e a API deixa
  /// de precisar montar a coleção inteira numa resposta só.
  Future<List<BarterModel>> list() async {
    final data = await api.getAll('/barters');
    return data.map(BarterModel.fromJson).toList();
  }

  Future<BarterModel> create({
    required String producerId,
    required String unitId,
    required Map<String, double> inputQuantities,
    TaxRegime taxRegime = TaxRegime.comercializacao,
  }) async {
    final data = await api.post('/barters', body: {
      'producerId': int.parse(producerId),
      // COMO o Funrural desta entrega é recolhido — a escolha do fechamento. A
      // ALÍQUOTA que ela produz é do servidor: a tabela é lei, e o app
      // instalado não pode ser a fonte dela.
      'taxRegime': taxRegime.apiValue,
      // A unidade de retirada. Ela decide de qual gerente é o parecer, e a
      // permuta nasce esperando por ele.
      'unitId': int.parse(unitId),
      'inputs': [
        for (final entry in inputQuantities.entries)
          if (entry.value > 0)
            {'productId': int.parse(entry.key), 'quantity': entry.value},
      ],
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// PARECER TÉCNICO do gerente da unidade — a etapa que move a permuta de
  /// "no gerente" para "no comitê".
  ///
  /// Repare que não há status no corpo: o parecer não aprova nem nega. O
  /// servidor recusa (403) se a permuta for de uma unidade de outro gerente.
  Future<BarterModel> giveOpinion(String code, String note) async {
    final data = await api.post('/barters/$code/opinion', body: {'note': note.trim()});
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// A DECISÃO DO COMITÊ (aprovar/negar). [code] é o id público (PRM-2026-001).
  ///
  /// Quem decide é o comitê — o admin administra o sistema e não passa por aqui.
  /// A rota continua sendo `/review`: o que mudou foi o papel, não a etapa.
  Future<BarterModel> review(String code, BarterStatus status, String note) async {
    final data = await api.post('/barters/$code/review', body: {
      'status': status.name,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O FATURAMENTO da permuta aprovada — o último posto da linha.
  ///
  /// Repare que não há status no corpo: o faturista não decide nada, ele fatura
  /// o que o comitê aprovou. O servidor recusa (422) o que não estiver aprovado.
  Future<BarterModel> invoice(String code, String note) async {
    final data = await api.post('/barters/$code/invoice', body: {
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O DETALHE de uma permuta — é ele que traz a LINHA DO TEMPO.
  ///
  /// A listagem não carrega histórico (lista mostra estado, não trajetória),
  /// então a tela de detalhe pede a permuta de novo para desenhar por onde ela
  /// passou. Ver [BarterModel.events].
  Future<BarterModel> find(String code) async {
    final data = await api.get('/barters/$code');
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }
}
