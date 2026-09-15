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

  /// Registra a permuta. Ela nasce RASCUNHO — na mão do consultor, e em fila
  /// nenhuma — até ele encaminhá-la com o parecer dele (ver [forward]).
  ///
  /// [note] é o parecer, para quem já o tem na hora de registrar: opcional aqui
  /// e obrigatório no encaminhamento, porque montar os insumos e ter a conversa
  /// com o produtor são dois momentos.
  Future<BarterModel> create({
    required String producerId,
    required String unitId,
    required Map<String, double> inputQuantities,
    String note = '',
  }) async {
    final data = await api.post('/barters', body: {
      'producerId': int.parse(producerId),
      if (note.trim().isNotEmpty) 'note': note.trim(),
      // SEM `taxRegime`: o regime é do produtor e mora no cadastro dele, e é de
      // lá que o servidor o lê. Mandá-lo daqui significaria mandar o que o
      // aparelho tinha guardado, que pode ser mais velho que o cadastro; e a
      // alíquota que ele produz é do servidor de qualquer forma, porque a
      // tabela é lei e o app instalado não pode ser a fonte dela.
      // A unidade de retirada — logística, e só: quem dá o parecer é o gerente
      // do CONSULTOR, e ele é definido no encaminhamento.
      'unitId': int.parse(unitId),
      'inputs': [
        for (final entry in inputQuantities.entries)
          if (entry.value > 0)
            {'productId': int.parse(entry.key), 'quantity': entry.value},
      ],
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O PARECER DO CONSULTOR gravado no rascunho, sem encaminhar nada.
  ///
  /// `PUT` porque é o mesmo texto sendo reescrito: é a única escrita do fluxo
  /// que se repete — as outras são atos, e ato repetido o servidor recusa. Só
  /// vale enquanto a permuta é rascunho; depois de encaminhada, o parecer fecha.
  Future<BarterModel> saveNote(String code, String note) async {
    final data = await api.put('/barters/$code/note', body: {'note': note.trim()});
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O ENCAMINHAMENTO ao gerente — o ato que tira a permuta da mesa do
  /// consultor e a põe na fila do parecer técnico.
  ///
  /// O parecer vai junto; [note] vazio manda o servidor usar o que já está
  /// salvo no rascunho. Sem texto nenhum, ele recusa (422) — encaminhar sem
  /// parecer seria um botão de "seguir" disfarçado.
  Future<BarterModel> forward(String code, String note) async {
    final data = await api.post('/barters/$code/forward', body: {
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// A TABELA DE VALORES com que esta permuta foi fechada.
  ///
  /// É o que a tela precisa para REMONTAR os insumos de um rascunho de uma
  /// gestão anterior: os preços da permuta são os daquela versão, e não os da
  /// vigente. Sem ela, o consultor montaria a permuta lendo um número e o
  /// servidor gravaria outro.
  ///
  /// Vem na moeda da LENTE, como a versão vigente: sacas por unidade para o
  /// consultor, R$ para a retaguarda.
  Future<BarterVersionModel> versionOf(String code) async {
    final data = await api.get('/barters/$code/version');
    return BarterVersionModel.fromJson(data as Map<String, dynamic>);
  }

  /// A REESCRITA DOS INSUMOS de um rascunho — a permuta remontada por quem a
  /// registrou, depois de o admin liberar a alteração (ou antes do primeiro
  /// encaminhamento).
  ///
  /// A lista vai INTEIRA, como no registro: a permuta passa pelas regras de
  /// mínimo como um conjunto, e o servidor a reprecifica pela tabela da versão
  /// em que ela foi fechada. Só vale enquanto ela é rascunho — depois disso o
  /// caminho é o pedido de alteração (ver [requestChange]).
  Future<BarterModel> replaceInputs(String code, Map<String, double> inputQuantities) async {
    final data = await api.put('/barters/$code/inputs', body: {
      'inputs': [
        for (final entry in inputQuantities.entries)
          if (entry.value > 0) {'productId': int.parse(entry.key), 'quantity': entry.value},
      ],
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O PEDIDO DE ALTERAÇÃO — o consultor pede ao admin que a permuta volte para
  /// ser refeita. Vale enquanto ela não foi faturada, e a justificativa é
  /// obrigatória: é ela a peça inteira do pedido, e é sobre ela que o admin
  /// decide.
  Future<BarterModel> requestChange(String code, String note) async {
    final data = await api.post('/barters/$code/change-request', body: {'note': note.trim()});
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// A DECISÃO DO ADMIN sobre o pedido: liberar (a permuta volta a rascunho, e
  /// o parecer do gerente e a decisão do comitê são apagados) ou recusar — e aí
  /// o motivo é obrigatório, como em toda resposta que fecha a porta de alguém.
  Future<BarterModel> decideChange(String code, {required bool accept, String note = ''}) async {
    final data = await api.post('/barters/$code/change-request/decision', body: {
      'accept': accept,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O ATENDIMENTO DO PEDIDO NO VALOR — a terceira saída do desvio.
  ///
  /// Em vez de devolver a permuta ao rascunho (e jogar fora o parecer do
  /// gerente e a decisão do comitê) para corrigir uma linha de R$, o admin
  /// corrige a linha: o servidor recalcula as sacas e a permuta continua
  /// exatamente onde estava.
  ///
  /// Só vale ATENDENDO a um pedido do consultor — sem pedido em aberto o
  /// servidor recusa (422). O admin não reprecifica permuta por conta própria.
  ///
  /// A lista leva só o que MUDA (o id do ITEM, não o do produto): a permuta
  /// está sendo corrigida linha a linha, e não remontada.
  Future<BarterModel> changePrices(
    String code,
    Map<String, double> valueByItemId, {
    String note = '',
  }) async {
    final data = await api.post('/barters/$code/change-request/prices', body: {
      'prices': [
        for (final entry in valueByItemId.entries)
          {'itemId': int.parse(entry.key), 'unitValue': entry.value},
      ],
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// O PEDIDO DE FORA DO BARTER — o consultor pede um produto que a tabela da
  /// versão não tem, para ESTA permuta.
  ///
  /// Sem valor no corpo, pela regra de sempre: preço nunca veio do cliente — e
  /// é justamente o item que ninguém precificou ainda. Vale do rascunho até a
  /// mesa do comitê; depois da decisão, o caminho é o pedido de alteração.
  Future<BarterModel> requestProduct(
    String code, {
    required String productName,
    required String unit,
    required double quantity,
    String note = '',
  }) async {
    final data = await api.post('/barters/$code/product-requests', body: {
      'productName': productName.trim(),
      'unit': unit.trim(),
      'quantity': quantity,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return BarterModel.fromJson(data as Map<String, dynamic>);
  }

  /// A DECISÃO DO ADMIN sobre o pedido de produto: incluir na permuta com o
  /// valor acertado, ou recusar — e aí o motivo é obrigatório.
  ///
  /// [productName], [unit], [quantity] e [sku] são CORREÇÕES do que o consultor
  /// escreveu: a descrição do fornecedor é outra, a embalagem é em 20 l e não em
  /// litro. Ausentes, valem os do pedido.
  Future<BarterModel> decideProduct(
    String code,
    String requestId, {
    required bool accept,
    double? unitValue,
    String? productName,
    String? unit,
    double? quantity,
    String? sku,
    String note = '',
  }) async {
    final data = await api.post('/barters/$code/product-requests/$requestId/decision', body: {
      'accept': accept,
      if (accept && unitValue != null) 'unitValue': unitValue,
      if (productName != null && productName.trim().isNotEmpty) 'productName': productName.trim(),
      if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      'quantity': ?quantity,
      if (sku != null && sku.trim().isNotEmpty) 'sku': sku.trim(),
      if (note.trim().isNotEmpty) 'note': note.trim(),
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

  /// A DECISÃO DO COMITÊ. [code] é o id público (PRM-2026-001).
  ///
  /// TRÊS saídas: aprovar, aprovar COM RESSALVA e negar. Nas duas últimas o
  /// texto é obrigatório e o servidor recusa sem ele — a exigência e a negativa
  /// criam trabalho para outra pessoa, e precisam dizer qual.
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

  /// A MESA DA CÉDULA (CPR) desta permuta: o rascunho, o que a permuta já
  /// responde, a credora configurada e o que ainda falta preencher.
  ///
  /// Uma chamada só, e de propósito: o formulário mistura as três fontes do
  /// documento, e montá-lo com uma requisição por fonte deixaria a tela
  /// desenhar campos vazios enquanto a sugestão não chega — que é exatamente o
  /// instante em que alguém começa a digitar o que já existia.
  ///
  /// É rota do FATURISTA (mesma capacidade do faturamento): a cédula é o
  /// documento que o posto dele produz.
  Future<CprDesk> cpr(String code) async {
    final data = await api.get('/barters/$code/cpr');
    return CprDesk.fromJson(data as Map<String, dynamic>);
  }

  /// Grava o preenchimento — inteiro ou pela metade, como ele estiver.
  ///
  /// O corpo vai completo (é o formulário que a tela devolve); quem decide que
  /// campo ausente preserva o gravado é o servidor. `areas` SUBSTITUI as
  /// lavouras, porque é uma lista editada como um todo na tela.
  Future<CprDesk> saveCpr(String code, CprDraft draft) async {
    final data = await api.put('/barters/$code/cpr', body: draft.toJson());
    return CprDesk.fromJson(data as Map<String, dynamic>);
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
