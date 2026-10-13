/// O POSTO DE CADA PESSOA NA LINHA DE PRODUÇÃO — qual é a fila dela e qual é a
/// etapa que ela acompanha.
///
/// Isso era uma `_Post.of(user)` dentro do painel da retaguarda, e a classe
/// guardava, no mesmo lugar, duas coisas de naturezas diferentes: a REGRA
/// (capacidade → fila → etapa vizinha) e a APARÊNCIA (cor, ícone, rótulo,
/// botão, texto de lista vazia). Mexer na aparência obrigava a reler a regra, e
/// a regra não tinha como ser testada sem montar a tela.
///
/// Aqui fica só a regra. A tela continua dona de como desenhar cada posto — e é
/// ela quem decide, por exemplo, que a fila do emissor abre a mesa da cédula.
library;

import '../models/models.dart';

/// Os postos que a permuta atravessa depois de sair da mão do consultor.
///
/// O ADMIN ocupa todos: ele tem todas as capacidades. Ver [workPostsOf].
enum WorkPost {
  /// O gerente: escreve o parecer técnico das permutas do time dele.
  manager,

  /// O comitê: decide (aprova, aprova com ressalva ou nega).
  committee,

  /// A seguradora: informa a apólice das aprovadas COM SEGURO. A permuta sem
  /// seguro não passa por ela.
  insurer,

  /// O faturista: fatura o que foi aprovado e anexa as notas.
  biller,

  /// O emissor: emite a cédula, colhe assinaturas e a leva a registro.
  emitter,
}

/// O posto desta pessoa, pela CAPACIDADE dela — nunca pelo nome do papel.
///
/// É a mesma leitura do servidor: quem participa de uma etapa é quem tem a
/// capacidade dela (ver `policy.ts`). Um papel novo que ganhe `barters.opinion`
/// amanhã cai na fila do parecer sem que esta função precise saber que ele
/// existe.
///
/// A ORDEM das perguntas importa quando alguém acumula capacidades: ela segue a
/// linha de produção, então quem opina e também decide aparece no posto mais
/// cedo — o trabalho que ele segura é o que trava a esteira antes.
WorkPost? workPostOf(UserModel user) {
  if (user.can(Capability.bartersOpinion)) return WorkPost.manager;
  if (user.can(Capability.bartersReview)) return WorkPost.committee;
  if (user.can(Capability.bartersInsure)) return WorkPost.insurer;
  if (user.can(Capability.bartersInvoice)) return WorkPost.biller;
  if (user.can(Capability.bartersCprIssue)) return WorkPost.emitter;
  return null;
}

/// TODOS os postos desta pessoa, na ordem da linha — para quem acumula etapas,
/// como o admin.
List<WorkPost> workPostsOf(UserModel user) => [
      if (user.can(Capability.bartersOpinion)) WorkPost.manager,
      if (user.can(Capability.bartersReview)) WorkPost.committee,
      if (user.can(Capability.bartersInsure)) WorkPost.insurer,
      if (user.can(Capability.bartersInvoice)) WorkPost.biller,
      if (user.can(Capability.bartersCprIssue)) WorkPost.emitter,
    ];

/// A FILA de um posto — o que espera ação dele agora.
///
/// A do GERENTE é a única com destinatário: o parecer é dele, e a permuta de
/// outro time não é assunto dele. As outras três são o ESTADO da permuta, como
/// no servidor: o comitê é um só, o faturamento é um posto só, a emissão também.
/// `managerId` nulo é a fila de TODOS os gerentes — a de quem enxerga a
/// operação inteira e pode dar parecer em qualquer uma (o admin).
///
/// A do EMISSOR tem os TRÊS degraus da cédula, e não só o primeiro: emitir,
/// assinar e registrar acontecem em dias diferentes, e uma fila com só "a
/// emitir" esconderia as cédulas assinadas paradas esperando cartório.
///
/// Toda fila sai da MAIS NOVA para a mais antiga, pela ordem dela mesma e não
/// pela da lista recebida: o cache local é mexido no lugar (a permuta registrada
/// entra no topo, a que muda de estado fica onde estava), e a fila não pode
/// herdar esses acasos.
List<BarterModel> queueOf(
  WorkPost post,
  List<BarterModel> barters, {
  String? managerId = '',
}) {
  final bool Function(BarterModel) waits;
  switch (post) {
    case WorkPost.manager:
      waits = managerId == null
          ? (b) => b.awaitsManager
          : (b) => b.awaitsOpinionFrom(managerId);
    case WorkPost.committee:
      waits = (b) => b.awaitsCommittee;
    case WorkPost.insurer:
      waits = (b) => b.awaitsPolicy;
    case WorkPost.biller:
      waits = (b) => b.awaitsInvoice;
    case WorkPost.emitter:
      waits = (b) => b.awaitsCprIssue || b.awaitsSignatures || b.awaitsRegistration;
  }
  final queue = barters.where(waits).toList();
  // No EMPATE de data vale a ordem recebida — a da API, que desempata pelo id.
  // O `sort` do Dart não é estável, então a posição entra na conta.
  final position = {for (final (i, b) in queue.indexed) b.id: i};
  return queue
    ..sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : position[a.id]!.compareTo(position[b.id]!);
    });
}

/// A ETAPA VIZINHA que este posto acompanha — o segundo número do painel.
///
/// Vizinha, e nunca uma etapa qualquer: para quem empurra a permuta adiante é a
/// SEGUINTE (o gerente vê o que já mandou ao comitê); para quem é fim de linha,
/// é o que ele já concluiu. O COMITÊ é o único que olha para TRÁS — o que está
/// no gerente é a fila que vai cair na mesa dele, e prever a fila é parte de
/// decidir.
///
/// Nenhum posto acompanha aqui uma etapa que ele não enxerga: o painel do
/// faturista mostrava "No comitê" enquanto ele lia a operação inteira, e era um
/// número que ele não podia abrir, conferir nem fazer nada a respeito.
BarterStatus followStatusOf(WorkPost post) {
  switch (post) {
    case WorkPost.manager:
      return BarterStatus.pending;
    case WorkPost.committee:
      return BarterStatus.sentToManager;
    // A SEGURADORA olha para a FRENTE, como o gerente: o que ela já liberou ao
    // faturista e ainda não foi faturado.
    case WorkPost.insurer:
      return BarterStatus.approved;
    case WorkPost.biller:
      return BarterStatus.invoiced;
    case WorkPost.emitter:
      return BarterStatus.cprRegistered;
  }
}

/// Quantas permutas estão na etapa vizinha, dentro do que esta pessoa enxerga.
int followCountOf(WorkPost post, List<BarterModel> barters) {
  final status = followStatusOf(post);
  return barters.where((b) => b.status == status).length;
}
