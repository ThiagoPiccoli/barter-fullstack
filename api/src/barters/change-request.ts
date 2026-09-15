import { BARTER_STATUS, type BarterStatus } from './barter-workflow';

/**
 * O PEDIDO DE ALTERAÇÃO — o caminho de volta da esteira.
 *
 * A esteira (`barter-workflow.ts`) só anda para a frente, e é assim de
 * propósito: cada posto recebe o que o anterior produziu e ninguém desfaz o ato
 * de outro. Mas a permuta erra DEPOIS de sair da mão de quem a montou — o
 * produtor troca um insumo na véspera da retirada, a quantidade saiu errada, a
 * conversa mudou. Sem um caminho de volta, as saídas eram duas e as duas ruins:
 * pedir ao comitê que NEGASSE (uma decisão de negócio usada como borracha, que
 * fica na história como negativa e some das metas) ou registrar uma segunda
 * permuta e deixar a primeira apodrecendo na fila de alguém.
 *
 * Este arquivo é a regra desse caminho, e ele mora FORA de `BARTER_STEPS` de
 * propósito: aquela tabela é a esteira, e é ela que desenha a checklist de
 * andamento (`progressOf`). Um "pedido de alteração" como etapa apareceria como
 * um quinto degrau pendente em toda permuta do sistema — quando ele é o
 * contrário de um degrau: um desvio que quase nenhuma permuta toma.
 *
 * ## Quem pede e quem decide
 *
 * Pede o CONSULTOR QUE REGISTROU — não o gerente, não o comitê. Os dois têm o
 * próprio ato para praticar sobre a permuta (devolver não é um deles), e quem
 * sabe que o combinado mudou é quem falou com o produtor.
 *
 * Decide o ADMIN. Ele não decide permuta (ver `CAPABILITY.bartersReview`), e
 * continua não decidindo: o que ele decide aqui é se o TRABALHO JÁ FEITO pelos
 * outros postos vai ser jogado fora — porque é isso que voltar ao rascunho faz
 * com o parecer do gerente e com a decisão do comitê. É administração do
 * processo, e não avaliação do negócio.
 *
 * ## Até quando
 *
 * Até o FATURAMENTO, e nem um passo além. A permuta faturada saiu para fora
 * (nota emitida, cédula assinada, insumo retirado) e corrigi-la aqui só criaria
 * uma divergência entre este sistema e o mundo — a correção de uma nota é ato
 * do sistema que a emitiu.
 *
 * O RASCUNHO também fica de fora, pela razão oposta: ele já está na mão do
 * consultor. Pedir permissão ao admin para mexer no que é seu seria burocracia
 * inventada, e o "pedido" nasceria concedido.
 */
export const CHANGE_REQUEST_STATUS = {
  /** Pedido feito, na mesa do admin. */
  open: 'open',
  /**
   * Pedido RECUSADO pelo admin, com o motivo escrito.
   *
   * Ele sobrevive à decisão, e o aceite não: o aceite fala pelo próprio efeito
   * (a permuta voltou a ser rascunho e está de novo com o consultor), enquanto
   * a recusa precisa continuar visível — sem ela, o consultor veria apenas a
   * permuta parada onde estava, sem nada dizendo que ele já pediu e ouviu não.
   */
  denied: 'denied',
} as const;

export type ChangeRequestStatus =
  (typeof CHANGE_REQUEST_STATUS)[keyof typeof CHANGE_REQUEST_STATUS];

/**
 * Os atos do desvio, como eles são gravados na linha do tempo da permuta
 * (`BarterEvent.action`).
 *
 * São três, e não dois, porque a linha do tempo conta O QUE ACONTECEU: "pedi",
 * "aceitaram" e "recusaram" são três fatos com autores diferentes, e o segundo
 * é o único que muda o estado da permuta.
 */
export const CHANGE_REQUEST_ACTION = {
  changeRequested: 'changeRequested',
  changeAccepted: 'changeAccepted',
  changeDenied: 'changeDenied',
} as const;

export type ChangeRequestAction =
  (typeof CHANGE_REQUEST_ACTION)[keyof typeof CHANGE_REQUEST_ACTION];

/** O rótulo de cada ato do desvio, na língua da operação. */
export const CHANGE_REQUEST_LABELS: Record<ChangeRequestAction, string> = {
  [CHANGE_REQUEST_ACTION.changeRequested]: 'Alteração solicitada',
  [CHANGE_REQUEST_ACTION.changeAccepted]: 'Alteração liberada',
  [CHANGE_REQUEST_ACTION.changeDenied]: 'Alteração recusada',
};

/** O bastante de uma permuta para saber se ela aceita um pedido, e por quê. */
export interface BarterAtRequest {
  status: string;
  changeRequestStatus?: string | null;
}

/**
 * POR QUE esta permuta não aceita um pedido de alteração agora — ou `null`,
 * quando aceita.
 *
 * Devolve a frase pronta, como `refusalFor` na esteira, e pelo mesmo motivo: a
 * pessoa que bate na porta fechada precisa saber o que fazer em seguida, e essa
 * resposta é do domínio, não da tela.
 */
export function changeRequestRefusal(barter: BarterAtRequest): string | null {
  if (barter.changeRequestStatus === CHANGE_REQUEST_STATUS.open) {
    return 'Já existe um pedido de alteração desta permuta aguardando o administrador';
  }
  if (barter.status === BARTER_STATUS.draft) {
    return 'Esta permuta é um rascunho seu: altere-a e encaminhe de novo, sem pedir nada a ninguém';
  }
  if (barter.status === BARTER_STATUS.invoiced) {
    return 'Esta permuta já foi faturada, e o que saiu para fora não se corrige por aqui';
  }
  return null;
}

/**
 * POR QUE não há o que decidir nesta permuta — ou `null`, quando há.
 *
 * A pergunta é só uma (existe pedido em aberto?), mas ela distingue dois casos
 * na resposta: nunca houve pedido, ou houve e já foi decidido. Quem chega pelo
 * segundo caminho é o admin que abriu a mesma tela em dois aparelhos, ou dois
 * admins na mesma permuta — e "não há pedido nenhum" o mandaria procurar um
 * defeito que não existe.
 */
export function changeDecisionRefusal(barter: BarterAtRequest): string | null {
  if (barter.changeRequestStatus === CHANGE_REQUEST_STATUS.open) return null;
  return barter.changeRequestStatus
    ? 'Este pedido de alteração já foi decidido'
    : 'Esta permuta não tem pedido de alteração em aberto';
}

/** O bastante de uma gestão do Barter para saber de que CULTURA ela é. */
export interface VersionAtCulture {
  code: string;
  season: { grainId: number | null; grainName: string };
}

/** Duas gestões do Barter são da MESMA cultura? */
function sameCulture(one: VersionAtCulture, other: VersionAtCulture): boolean {
  const oneId = one.season.grainId;
  const otherId = other.season.grainId;
  // Pelo id do grão quando os dois têm: é ele que identifica a cultura. O nome
  // é a saída para a safra cujo produto foi excluído do catálogo (o FK vira
  // null e sobra o nome congelado) — comparar nomes sempre seria frágil; nunca
  // compará-los deixaria essas safras fora de qualquer alteração.
  if (oneId !== null && otherId !== null) return oneId === otherId;
  return one.season.grainName.trim().toLowerCase() === other.season.grainName.trim().toLowerCase();
}

/**
 * POR QUE esta permuta não pode ser alterada NESTA gestão do Barter, ou `null`
 * quando pode.
 *
 * A alteração atravessa VERSÕES, e não atravessa CULTURAS. A permuta fechada na
 * primeira versão da soja continua alterável quando a terceira já está no ar:
 * ela ainda não foi faturada, o produtor é o mesmo, a lavoura é a mesma, e o
 * que ela precisa é de uma correção nos insumos, não de um recomeço. Amarrá-la
 * à versão vigente transformaria cada publicação de tabela num prazo de
 * validade para as permutas em aberto.
 *
 * O que ela não atravessa é a CULTURA. Com o Barter do milho no ar, uma permuta
 * de soja não é mais o negócio da praça: os insumos que ela pode carregar, os
 * mínimos por hectare e o grão que a paga são outros, e remontá-la ali seria
 * montar uma permuta de soja com a régua do milho. Nesse caso o caminho é o
 * mesmo de sempre — o comitê decide o que fazer com ela.
 *
 * Os PREÇOS continuam sendo os da versão DA PERMUTA, e não os da vigente: o
 * acordo foi fechado naquela tabela, e publicar a seguinte não reescreve o que
 * já foi combinado. É o mesmo motivo de o item guardar o preço em vez de lê-lo.
 */
export function cultureRefusal(
  barterVersion: VersionAtCulture,
  openVersion: VersionAtCulture,
): string | null {
  if (sameCulture(barterVersion, openVersion)) return null;
  return (
    `Esta permuta é do Barter ${barterVersion.code}, de ${barterVersion.season.grainName}, ` +
    `e o que está aberto hoje é ${openVersion.season.grainName} (${openVersion.code}). ` +
    'A alteração vale entre versões da mesma cultura'
  );
}

/**
 * O QUE O ACEITE APAGA da permuta que volta ao rascunho.
 *
 * Voltar ao rascunho é desfazer as etapas cumpridas, e desfazê-las é apagar o
 * que elas escreveram: o parecer do gerente e a decisão do comitê falavam de
 * uma permuta que está prestes a mudar, e mantê-los seria pendurar uma
 * aprovação sobre insumos que ninguém aprovou. A tela leria "Decidida por
 * Fulano" numa permuta em rascunho, e o comprovante imprimiria a decisão junto
 * com os itens novos.
 *
 * Nada disso se perde: cada um desses atos tem EVENTO gravado
 * (`BarterEvent`), com autor, texto e data, e a linha do tempo continua
 * contando que houve parecer e que houve decisão. O que é apagado é o estado
 * ATUAL — que passou a ser falso —, não a história.
 *
 * O parecer do CONSULTOR (`consultantNote`) sobrevive: é o texto dele sobre o
 * próprio cliente, ele vai reencaminhar a permuta, e apagá-lo seria pedir que
 * reescrevesse do zero o que continua valendo. `consultantSentAt` cai porque o
 * envio, esse sim, deixou de ter acontecido.
 */
export const CLEARED_BY_CHANGE = {
  consultantSentAt: null,
  managerId: null,
  managerName: null,
  managerNote: null,
  managerReviewedAt: null,
  reviewNote: null,
  reviewedBy: null,
  reviewedById: null,
  reviewedAt: null,
} as const;

/** O estado em que o pedido foi feito, para a linha do tempo poder dizê-lo. */
export function requestedFrom(barter: { changeRequestFrom?: string | null }): BarterStatus | null {
  return (barter.changeRequestFrom as BarterStatus | null | undefined) ?? null;
}
