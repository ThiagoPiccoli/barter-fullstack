import { CAPABILITY, type Capability } from '../common/policy';
import { ROLE, type Role } from '../common/roles';

/**
 * A LINHA DE PRODUÇÃO da permuta: por quais estados ela passa, quem a empurra
 * de um para o outro e o que responder a quem chega fora de hora.
 *
 * Existe porque o fluxo deixou de caber em `if`s. Enquanto eram duas etapas
 * (parecer e revisão), o `barters.service.ts` conseguia carregar as regras na
 * mão — três comparações de string espalhadas por dois métodos. Com quatro
 * postos e cinco estados, cada etapa nova exigiria reler os outros métodos para
 * descobrir quem mais olha `status`, e a pergunta "de onde uma permuta faturada
 * pode ter vindo?" não teria nenhum arquivo onde ser respondida.
 *
 * Aqui ela tem. A tabela abaixo é a única definição do caminho:
 *
 *     (registro)                                    ┌──────────┐
 *         │                                         │ invoiced │  fim da linha
 *         ▼                                         └──────────┘
 *   sentToManager ──parecer──▶ pending ──aprova──▶ approved ──fatura──▶
 *    (gerente)                (comitê)             (faturista)
 *                                 │
 *                                 └──nega──▶ denied  (fim da linha)
 *
 * Cada posto tem UM dono e UMA pergunta:
 *
 * - **gerente**: conhece o produtor e a negociação — escreve o parecer técnico.
 *   Não decide;
 * - **comitê**: lê o pedido do consultor e o parecer do gerente e DECIDE. É a
 *   única instância que aprova ou nega. O admin não decide — ele administra o
 *   sistema, e um administrador que também aprova é a mesma pessoa concedendo o
 *   acesso e usando-o;
 * - **faturista**: recebe o que as etapas anteriores produziram e FATURA. Só
 *   alcança o que foi aprovado, e é o fim da linha.
 *
 * O que este arquivo NÃO decide: quem é o gerente DESTA permuta (é o do
 * consultor, gravado no envio) nem qualquer alçada por valor. Isso é política
 * sobre o recurso e mora no service — ver o comentário no fim de `policy.ts`.
 */

export const BARTER_STATUS = {
  /** Registrada pelo consultor, na mesa do gerente dele, esperando parecer. */
  sentToManager: 'sentToManager',
  /**
   * Com parecer do gerente, na mesa do COMITÊ, esperando decisão.
   *
   * O nome ficou de quando a revisão era do admin, e ficou de propósito: ele
   * descreve o estado ("esperando alguém decidir"), não o cargo de quem decide,
   * e é o que está gravado nas permutas que já existem. Trocá-lo por
   * `atCommittee` renomearia dado histórico para dizer a mesma coisa.
   */
  pending: 'pending',
  /** Aprovada pelo comitê — a fila do faturista. */
  approved: 'approved',
  /** Negada pelo comitê. Fim da linha: não fatura e não volta. */
  denied: 'denied',
  /** Faturada. Fim da linha do lado bom. */
  invoiced: 'invoiced',
} as const;

export type BarterStatus = (typeof BARTER_STATUS)[keyof typeof BARTER_STATUS];

/**
 * A ESTEIRA, na ordem em que se anda nela. `denied` fica fora: ele é saída
 * lateral, não um degrau adiante — e é essa lista que diz se quem pede uma ação
 * chegou cedo demais ou tarde demais (ver `refusalFor`).
 */
export const BARTER_LINE = [
  BARTER_STATUS.sentToManager,
  BARTER_STATUS.pending,
  BARTER_STATUS.approved,
  BARTER_STATUS.invoiced,
] as const;

/** Todos os estados possíveis — é o que valida o filtro `?status=` da listagem. */
export const BARTER_STATUSES = [...BARTER_LINE, BARTER_STATUS.denied] as const;

/** O rótulo de cada estado, na língua da operação. */
export const BARTER_STATUS_LABELS: Record<BarterStatus, string> = {
  [BARTER_STATUS.sentToManager]: 'No gerente',
  [BARTER_STATUS.pending]: 'No comitê',
  [BARTER_STATUS.approved]: 'Aprovada — a faturar',
  [BARTER_STATUS.denied]: 'Negada',
  [BARTER_STATUS.invoiced]: 'Faturada',
};

/**
 * COM QUEM a permuta está parada agora — o papel que precisa agir para ela
 * andar. Null nos dois fins de linha, onde não há próximo passo.
 *
 * É o que o app usa para dizer "esperando o comitê" sem manter uma segunda
 * cópia do fluxo em Dart.
 */
export const BARTER_HOLDER: Record<BarterStatus, Role | null> = {
  [BARTER_STATUS.sentToManager]: ROLE.manager,
  [BARTER_STATUS.pending]: ROLE.committee,
  [BARTER_STATUS.approved]: ROLE.biller,
  [BARTER_STATUS.denied]: null,
  [BARTER_STATUS.invoiced]: null,
};

/** Os atos que movem uma permuta. `register` é a entrada: cria em vez de mover. */
export const BARTER_ACTION = {
  register: 'register',
  opinion: 'opinion',
  review: 'review',
  invoice: 'invoice',
} as const;

export type BarterAction = (typeof BARTER_ACTION)[keyof typeof BARTER_ACTION];

/** O bastante de uma permuta para decidir se ela pode andar, e para explicar por quê. */
export interface BarterAtStep {
  status: string;
  managerName?: string | null;
}

export interface WorkflowStep {
  readonly action: BarterAction;
  /** De onde ela sai. `null` só no registro, que não sai de lugar nenhum. */
  readonly from: BarterStatus | null;
  /** Para onde ela vai. Mais de um quando o ato é uma DECISÃO (aprova/nega). */
  readonly to: readonly BarterStatus[];
  /** A capacidade que abre a porta — a mesma que o decorator da rota exige. */
  readonly capability: Capability;
  /**
   * O que dizer a quem chega CEDO: a permuta ainda está parada nesta etapa, e
   * quem pediu a ação é de uma etapa adiante.
   */
  readonly waiting: (barter: BarterAtStep) => string;
  /** O que dizer a quem chega TARDE: esta etapa já foi cumprida. */
  readonly done: string;
}

/**
 * A TABELA. Uma etapa nova é uma entrada aqui — e o `Record` obriga a escrever
 * as duas mensagens junto com ela, que é a parte que se esquece: sem elas, a
 * pessoa que chega fora de hora recebe "não foi possível" e vai perguntar a
 * alguém onde a permuta parou.
 */
export const BARTER_STEPS: Record<BarterAction, WorkflowStep> = {
  [BARTER_ACTION.register]: {
    action: BARTER_ACTION.register,
    from: null,
    to: [BARTER_STATUS.sentToManager],
    capability: CAPABILITY.bartersRegister,
    waiting: () => 'Esta permuta ainda não foi registrada',
    done: 'Esta permuta já foi registrada',
  },
  [BARTER_ACTION.opinion]: {
    action: BARTER_ACTION.opinion,
    from: BARTER_STATUS.sentToManager,
    to: [BARTER_STATUS.pending],
    capability: CAPABILITY.bartersOpinion,
    waiting: (barter) =>
      `Esta permuta aguarda o parecer do gerente ${barter.managerName ?? 'responsável'}`,
    done: 'Esta permuta já recebeu o parecer do gerente',
  },
  [BARTER_ACTION.review]: {
    action: BARTER_ACTION.review,
    from: BARTER_STATUS.pending,
    to: [BARTER_STATUS.approved, BARTER_STATUS.denied],
    capability: CAPABILITY.bartersReview,
    waiting: () => 'Esta permuta aguarda a decisão do comitê',
    done: 'Esta permuta já foi decidida pelo comitê',
  },
  [BARTER_ACTION.invoice]: {
    action: BARTER_ACTION.invoice,
    from: BARTER_STATUS.approved,
    to: [BARTER_STATUS.invoiced],
    capability: CAPABILITY.bartersInvoice,
    waiting: () => 'Esta permuta aguarda o faturamento',
    done: 'Esta permuta já foi faturada',
  },
};

/** A etapa que age sobre uma permuta parada neste estado, se houver. */
export function stepAt(status: string): WorkflowStep | undefined {
  return Object.values(BARTER_STEPS).find((step) => step.from === status);
}

/** O próximo ato que esta permuta espera — `undefined` nos fins de linha. */
export function nextActionOf(status: string): BarterAction | undefined {
  return stepAt(status)?.action;
}

/**
 * POR QUE esta permuta não pode receber este ato agora — ou `null`, quando pode.
 *
 * A resposta distingue as três maneiras de dar errado, porque elas mandam a
 * pessoa fazer coisas diferentes:
 *
 * - **chegou cedo**: a etapa anterior não terminou. Dizer "já foi decidida" a
 *   quem espera o comitê o mandaria procurar uma decisão que ninguém tomou — o
 *   que ele precisa saber é com quem a permuta está parada;
 * - **chegou tarde**: a etapa dele já foi cumprida;
 * - **negada**: fim da linha, e nenhuma das duas explicações serve.
 *
 * Isto é a REGRA, não a autorização: quem pode chamar a rota é a capacidade do
 * passo (`step.capability`), conferida pelo AccessGuard antes de a permuta ser
 * lida.
 */
export function refusalFor(action: BarterAction, barter: BarterAtStep): string | null {
  const step = BARTER_STEPS[action];
  if (step.from === null || barter.status === step.from) return null;

  if (barter.status === BARTER_STATUS.denied) {
    return 'Esta permuta foi negada pelo comitê';
  }

  const here = (BARTER_LINE as readonly string[]).indexOf(barter.status);
  const there = (BARTER_LINE as readonly string[]).indexOf(step.from);

  // Estado que não está na esteira: dado de uma versão futura do servidor, ou
  // escrito à mão no banco. Recusa sem inventar uma explicação.
  if (here < 0) return 'Esta permuta está em uma etapa que não permite esta ação';

  return here < there ? (stepAt(barter.status)?.waiting(barter) ?? step.done) : step.done;
}
