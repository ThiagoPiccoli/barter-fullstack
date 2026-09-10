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
    TaxRegime taxRegime = TaxRegime.comercializacao,
    String note = '',
  }) async {
    final data = await api.post('/barters', body: {
      'producerId': int.parse(producerId),
      if (note.trim().isNotEmpty) 'note': note.trim(),
      // COMO o Funrural desta entrega é recolhido — a escolha do fechamento. A
      // ALÍQUOTA que ela produz é do servidor: a tabela é lei, e o app
      // instalado não pode ser a fonte dela.
      'taxRegime': taxRegime.apiValue,
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
