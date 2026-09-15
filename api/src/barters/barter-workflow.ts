import { CAPABILITY, rolesWith, type Capability } from '../common/policy';
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
 *     (registro)                             ┌──────────────────────────┐
 *         │                                  │ approvedWithConditions   │
 *         ▼                                  └───────────┬──────────────┘
 *      draft ──encaminha──▶ sentToManager ──parecer──▶ pending
 *   (consultor)              (gerente)                (comitê)
 *                                                        │  ├─aprova──▶ approved ──fatura──▶ invoiced
 *                                                        │  └─ressalva─▶ approvedWithConditions ──┘
 *                                                        └──nega──▶ denied  (fim da linha)
 *
 * Cada posto tem UM dono e UMA pergunta:
 *
 * - **consultor**: monta a negociação e escreve o PARECER dele sobre o próprio
 *   cliente. Enquanto ele não encaminha, a permuta é rascunho e não está na mesa
 *   de ninguém — ver `draft`;
 * - **gerente**: conhece o produtor e a negociação — escreve o parecer técnico.
 *   Não decide;
 * - **comitê**: lê o pedido do consultor, o parecer dele e o parecer do gerente,
 *   e DECIDE. É a única instância que aprova, aprova COM RESSALVA ou nega. O
 *   admin não decide — ele administra o sistema, e um administrador que também
 *   aprova é a mesma pessoa concedendo o acesso e usando-o;
 * - **faturista**: recebe o que as etapas anteriores produziram e FATURA. Só
 *   alcança o que foi aprovado (com ou sem ressalva), e é o fim da linha.
 *
 * O que este arquivo NÃO decide: quem é o gerente DESTA permuta (é o do
 * consultor, gravado no envio) nem qualquer alçada por valor. Isso é política
 * sobre o recurso e mora no service — ver o comentário no fim de `policy.ts`.
 */

export const BARTER_STATUS = {
  /**
   * RASCUNHO do consultor: registrada, mas ainda não encaminhada.
   *
   * É o único estado que não está na mesa de ninguém, e é isso que ele existe
   * para dar: o consultor monta a permuta hoje, escreve o parecer dela quando
   * tiver a conversa com o produtor, e só então encaminha. Antes disso, o
   * registro já vale — os valores da versão ficam congelados nele — mas nenhuma
   * fila da retaguarda o enxerga.
   *
   * Rascunho é DO DONO: `scopeFor`, no service, o esconde de quem não o
   * registrou. Uma permuta pela metade na fila do comitê seria trabalho pedido
   * a quem não foi chamado.
   */
  draft: 'draft',
  /** Encaminhada pelo consultor, na mesa do gerente dele, esperando parecer. */
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
  /**
   * Aprovada pelo comitê COM RESSALVA — a mesma fila do faturista, e uma
   * exigência escrita junto.
   *
   * É estado próprio, e não um `approved` com um campo ao lado, porque a
   * ressalva é uma CONDIÇÃO do negócio (garantia real, seguro obrigatório,
   * aval) e quem a cumpre não é quem a escreveu. Enquanto ela fosse uma
   * observação dentro da aprovação, a lista, o filtro e o cartão diriam
   * "Aprovada — a faturar" sobre uma permuta que só pode ser faturada depois de
   * alguém providenciar um aval — e a única maneira de descobrir isso seria
   * abrir a permuta e ler até o fim.
   *
   * O que ela NÃO é: um estado de espera. A permuta está decidida e liberada; o
   * comitê exigiu algo junto, e o texto da decisão (`reviewNote`, obrigatório
   * aqui) diz o quê. Cobrar o cumprimento é da operação, não deste fluxo — o
   * dia em que for do fluxo, isto vira uma etapa com dono, e não um campo.
   */
  approvedWithConditions: 'approvedWithConditions',
  /** Negada pelo comitê. Fim da linha: não fatura e não volta. */
  denied: 'denied',
  /** Faturada. Fim da linha do lado bom. */
  invoiced: 'invoiced',
} as const;

export type BarterStatus = (typeof BARTER_STATUS)[keyof typeof BARTER_STATUS];

/**
 * A ESTEIRA, na ordem em que se anda nela — e cada degrau é uma LISTA.
 *
 * Ela era uma fila simples de estados, um por degrau, e deixou de poder ser
 * quando a decisão do comitê ganhou a terceira saída: `approved` e
 * `approvedWithConditions` são o MESMO ponto da linha (a mesa do faturista) com
 * desfechos diferentes. Com a lista antiga, o único jeito de a segunda ser
 * alcançável pelo faturamento era pô-la um degrau adiante da primeira — e aí
 * uma permuta aprovada com ressalva passaria a ser "tarde demais para faturar",
 * porque a posição na esteira é justamente o que responde cedo/tarde.
 *
 * `denied` fica fora: ele é saída lateral, não um degrau adiante.
 */
export const BARTER_LINE = [
  [BARTER_STATUS.draft],
  [BARTER_STATUS.sentToManager],
  [BARTER_STATUS.pending],
  [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions],
  [BARTER_STATUS.invoiced],
] as const satisfies readonly (readonly BarterStatus[])[];

/** Em que DEGRAU da esteira este estado está — `-1` fora dela (só `denied`). */
export function stageOf(status: string): number {
  return BARTER_LINE.findIndex((stage) => (stage as readonly string[]).includes(status));
}

/** Todos os estados possíveis — é o que valida o filtro `?status=` da listagem. */
export const BARTER_STATUSES = [...BARTER_LINE.flat(), BARTER_STATUS.denied] as const;

/** O rótulo de cada estado, na língua da operação. */
export const BARTER_STATUS_LABELS: Record<BarterStatus, string> = {
  [BARTER_STATUS.draft]: 'Rascunho',
  [BARTER_STATUS.sentToManager]: 'No gerente',
  [BARTER_STATUS.pending]: 'No comitê',
  [BARTER_STATUS.approved]: 'Aprovada, a faturar',
  [BARTER_STATUS.approvedWithConditions]: 'Aprovada com ressalva, a faturar',
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
  // O rascunho está com QUEM O ESCREVEU. É o único estado em que o dono da vez
  // é o consultor, e dizê-lo é a diferença entre "esperando você" e uma permuta
  // que parece parada por culpa da retaguarda.
  [BARTER_STATUS.draft]: ROLE.consultant,
  [BARTER_STATUS.sentToManager]: ROLE.manager,
  [BARTER_STATUS.pending]: ROLE.committee,
  [BARTER_STATUS.approved]: ROLE.biller,
  [BARTER_STATUS.approvedWithConditions]: ROLE.biller,
  [BARTER_STATUS.denied]: null,
  [BARTER_STATUS.invoiced]: null,
};

/** Os atos que movem uma permuta. `register` é a entrada: cria em vez de mover. */
export const BARTER_ACTION = {
  register: 'register',
  forward: 'forward',
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
  /**
   * De onde ela sai. `null` só no registro, que não sai de lugar nenhum.
   *
   * É uma LISTA pelo mesmo motivo do degrau da esteira: o faturamento parte de
   * `approved` e de `approvedWithConditions`, que são o mesmo ponto da linha. O
   * primeiro da lista é o representante do degrau — é dele que sai o cálculo de
   * cedo/tarde e o alcance de `lineFrom`.
   */
  readonly from: readonly BarterStatus[] | null;
  /** Para onde ela vai. Mais de um quando o ato é uma DECISÃO (aprova/nega). */
  readonly to: readonly BarterStatus[];
  /** A capacidade que abre a porta — a mesma que o decorator da rota exige. */
  readonly capability: Capability;
  /**
   * O NOME da etapa — o que ela é, e não o que ela virou.
   *
   * Substantivo, e de propósito: o mesmo rótulo serve à etapa cumprida, à que
   * está acontecendo e à que ainda vem. "Parecer do gerente" se lê igual nos
   * três estados; "Aprovada pelo comitê" só se lê depois, e uma checklist é
   * feita principalmente do que ainda não aconteceu.
   */
  readonly label: string;
  /**
   * COMO a etapa terminou, quando ela pode terminar de mais de um jeito.
   *
   * Só a decisão do comitê tem: as outras empurram adiante e nada mais, e
   * carimbar "Faturamento: faturada" seria repetir o nome da etapa. Quem
   * resolve o rótulo é o EVENTO gravado (ver `outcomeLabelOf`), não o estado
   * atual da permuta — uma permuta faturada está em `invoiced`, e a decisão que
   * a levou até lá continua tendo sido "Aprovada".
   */
  readonly outcomes?: Partial<Record<BarterStatus, string>>;
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
    to: [BARTER_STATUS.draft],
    capability: CAPABILITY.bartersRegister,
    label: 'Registro do consultor',
    waiting: () => 'Esta permuta ainda não foi registrada',
    done: 'Esta permuta já foi registrada',
  },
  /**
   * O PARECER DO CONSULTOR e o encaminhamento — um ato só, e de propósito.
   *
   * Ele é quem conhece o cliente: safras anteriores, pontualidade, o que está
   * plantado e o que a lavoura promete. Isso não estava em lugar nenhum do
   * registro — a permuta chegava ao gerente como uma lista de insumos, e o que
   * o consultor sabia ficava no telefonema que ele dava depois.
   *
   * Encaminhar SEM parecer não existe: o texto é o próprio ato (ver
   * `ForwardBarterDto`). Mas escrevê-lo sem encaminhar existe, e é o que
   * `PUT /barters/:code/note` faz — o rascunho é salvável pela metade, porque a
   * conversa com o produtor não acontece no mesmo minuto em que se montam os
   * insumos.
   */
  [BARTER_ACTION.forward]: {
    action: BARTER_ACTION.forward,
    from: [BARTER_STATUS.draft],
    to: [BARTER_STATUS.sentToManager],
    capability: CAPABILITY.bartersRegister,
    label: 'Parecer do consultor',
    waiting: () => 'Esta permuta é um rascunho e ainda não foi encaminhada ao gerente',
    done: 'Esta permuta já foi encaminhada ao gerente',
  },
  [BARTER_ACTION.opinion]: {
    action: BARTER_ACTION.opinion,
    from: [BARTER_STATUS.sentToManager],
    to: [BARTER_STATUS.pending],
    capability: CAPABILITY.bartersOpinion,
    label: 'Parecer do gerente',
    waiting: (barter) =>
      `Esta permuta aguarda o parecer do gerente ${barter.managerName ?? 'responsável'}`,
    done: 'Esta permuta já recebeu o parecer do gerente',
  },
  [BARTER_ACTION.review]: {
    action: BARTER_ACTION.review,
    from: [BARTER_STATUS.pending],
    // TRÊS saídas. `approved` é a primeira porque é ela que representa o degrau
    // na esteira (ver `from` em WorkflowStep) — as outras duas são desfechos do
    // mesmo ato, não pontos diferentes da linha.
    to: [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions, BARTER_STATUS.denied],
    capability: CAPABILITY.bartersReview,
    label: 'Decisão do comitê',
    outcomes: {
      [BARTER_STATUS.approved]: 'Aprovada',
      [BARTER_STATUS.approvedWithConditions]: 'Aprovada com ressalva',
      [BARTER_STATUS.denied]: 'Negada',
    },
    waiting: () => 'Esta permuta aguarda a decisão do comitê',
    done: 'Esta permuta já foi decidida pelo comitê',
  },
  [BARTER_ACTION.invoice]: {
    action: BARTER_ACTION.invoice,
    // As duas aprovações faturam. A ressalva é condição do negócio, não um
    // portão deste fluxo — ver `approvedWithConditions`.
    from: [BARTER_STATUS.approved, BARTER_STATUS.approvedWithConditions],
    to: [BARTER_STATUS.invoiced],
    capability: CAPABILITY.bartersInvoice,
    label: 'Faturamento',
    waiting: () => 'Esta permuta aguarda o faturamento',
    done: 'Esta permuta já foi faturada',
  },
};

/** A etapa que age sobre uma permuta parada neste estado, se houver. */
export function stepAt(status: string): WorkflowStep | undefined {
  return Object.values(BARTER_STEPS).find((step) =>
    (step.from as readonly string[] | null)?.includes(status),
  );
}

/**
 * A esteira A PARTIR de um posto: o estado em que ele age e tudo o que vem
 * depois — ou seja, o que JÁ CHEGOU nele.
 *
 * É o que define o alcance de quem só enxerga o próprio trecho da linha. O
 * faturista é o caso: ele recebe o que as etapas anteriores produziram, e o que
 * ainda está no gerente ou no comitê não é trabalho dele nem informação dele.
 *
 * Vem da esteira, e não de uma lista escrita à mão no service, porque a resposta
 * MUDA quando a linha muda: uma etapa nova depois do faturamento entra sozinha
 * no alcance do faturista, e uma etapa nova antes dele fica de fora sozinha.
 * Repare que `denied` não está em [BARTER_LINE] e por isso nunca aparece aqui —
 * uma permuta negada morre no comitê e não chega ao faturamento.
 */
export function lineFrom(action: BarterAction): BarterStatus[] {
  const from = BARTER_STEPS[action].from;
  const at = from === null ? 0 : stageOf(from[0]);
  return at < 0 ? [] : BARTER_LINE.slice(at).flatMap((stage) => [...stage]);
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
  if (step.from === null || (step.from as readonly string[]).includes(barter.status)) return null;

  if (barter.status === BARTER_STATUS.denied) {
    return 'Esta permuta foi negada pelo comitê';
  }

  const here = stageOf(barter.status);
  const there = stageOf(step.from[0]);

  // Estado que não está na esteira: dado de uma versão futura do servidor, ou
  // escrito à mão no banco. Recusa sem inventar uma explicação.
  if (here < 0) return 'Esta permuta está em uma etapa que não permite esta ação';

  return here < there ? (stepAt(barter.status)?.waiting(barter) ?? step.done) : step.done;
}

/* ── O ANDAMENTO: a linha inteira, e não só o trecho já andado ─────────── */

/**
 * Em que pé está uma etapa DESTA permuta.
 *
 * Existe porque "por onde ela passou" e "o que ainda falta" são a mesma
 * pergunta feita dos dois lados, e quem abre uma permuta faz as duas. A linha do
 * tempo dos eventos só responde à primeira: uma permuta parada no comitê mostra
 * dois passos e cala sobre os dois que faltam — e "falta o quê, e com quem?" é
 * justamente o que o consultor veio perguntar, porque é o que ele vai ter de
 * responder ao produtor.
 */
export const BARTER_STEP_STATE = {
  /** Cumprida. É a parte que tem evento gravado. */
  done: 'done',
  /** É AQUI que a permuta está parada agora. */
  current: 'current',
  /** Ainda vai acontecer. */
  ahead: 'ahead',
  /**
   * NÃO vai acontecer: a permuta saiu da linha antes de chegar aqui.
   *
   * Diferente de `ahead` de propósito. Uma permuta negada nunca fatura, e
   * mostrar o faturamento dela como etapa pendente prometeria um passo que
   * ninguém vai dar — o pior tipo de erro numa tela de acompanhamento, porque
   * quem lê fica esperando.
   */
  halted: 'halted',
} as const;

export type BarterStepState = (typeof BARTER_STEP_STATE)[keyof typeof BARTER_STEP_STATE];

/** Uma etapa da esteira vista de dentro de uma permuta concreta. */
export interface BarterProgressStep {
  readonly action: BarterAction;
  readonly state: BarterStepState;
  /** O nome da etapa — ver `label` em [WorkflowStep]. */
  readonly label: string;
  /** O papel dono dela: quem a cumpriu, ou quem ainda vai cumpri-la. */
  readonly role: Role | null;
  /**
   * O que há para dizer sobre o ESTADO desta etapa, por extenso:
   *
   * - na etapa de agora, o que ela espera ("aguarda a decisão do comitê");
   * - na que não vai acontecer, por que não ("a permuta foi negada").
   *
   * Null nas cumpridas — elas se explicam sozinhas, com o autor e a data — e
   * nas que ainda vêm, onde não há nada a dizer além do nome e do dono.
   *
   * A frase sai daqui, e não da tela, porque o motivo é do FLUXO: uma saída
   * lateral nova (uma permuta cancelada, digamos) chegaria escrita certa no app
   * já instalado, em vez de ele continuar dizendo "foi negada" sobre uma
   * permuta que não foi.
   */
  readonly stateNote: string | null;
}

/** A POSIÇÃO da etapa na esteira — o degrau do estado que ela produz. */
function orderOf(step: WorkflowStep): number {
  return stageOf(step.to[0]);
}

/**
 * O papel dono da etapa, tirado da CAPACIDADE que a abre.
 *
 * Não é um campo da tabela porque seria a mesma verdade escrita duas vezes: a
 * política já diz quem tem `barters.review`, e uma etapa cuja capacidade
 * pertencesse a dois papéis seria uma etapa sem dono — o que os testes da
 * máquina de estados já não deixam acontecer.
 */
function ownerOf(step: WorkflowStep): Role | null {
  return rolesWith(step.capability)[0] ?? null;
}

/**
 * O CAMINHO INTEIRO desta permuta, etapa por etapa, do registro ao faturamento.
 *
 * É a esteira vista de dentro de uma permuta: as mesmas quatro etapas de
 * [BARTER_STEPS], na mesma ordem, cada uma dizendo em que pé está. Sai daqui, e
 * não de uma lista escrita à mão no app, pelo motivo de sempre — uma etapa nova
 * aparece nas telas já instaladas em vez de exigir versão nova, e o Dart não
 * ganha uma segunda cópia do fluxo para sair de sincronia com esta.
 *
 * Estado que nenhuma etapa produz (banco adulterado, ou um servidor à frente
 * deste) devolve lista VAZIA: a tela cai na linha do tempo dos eventos, que é
 * fato gravado, em vez de desenhar um caminho inventado.
 */
export function progressOf(barter: BarterAtStep): BarterProgressStep[] {
  const steps = Object.values(BARTER_STEPS);
  const here = stageOf(barter.status);

  // SAÍDA LATERAL (hoje só a negativa): fora da esteira, mas produzida por
  // alguma etapa. Essa etapa foi cumprida — e o que vinha depois dela não vem.
  const exit =
    here < 0
      ? steps.find((step) => (step.to as readonly string[]).includes(barter.status))
      : undefined;

  if (here < 0 && !exit) return [];

  const lastDone = exit ? orderOf(exit) : here;
  const now = stepAt(barter.status);

  // POR QUE a linha parou, quando ela parou — dito a partir do estado em que a
  // permuta saiu, e não de uma frase escrita para a negativa: uma saída lateral
  // nova é uma linha na tabela de estados, e esta frase a acompanha.
  const stoppedNote = exit
    ? `Não acontece: a permuta foi ${(
        BARTER_STATUS_LABELS[barter.status as BarterStatus] ?? barter.status
      ).toLowerCase()}`
    : null;

  return steps.map((step) => {
    const state =
      orderOf(step) <= lastDone
        ? BARTER_STEP_STATE.done
        : exit
          ? BARTER_STEP_STATE.halted
          : step === now
            ? BARTER_STEP_STATE.current
            : BARTER_STEP_STATE.ahead;

    return {
      action: step.action,
      state,
      label: step.label,
      role: ownerOf(step),
      stateNote:
        state === BARTER_STEP_STATE.current
          ? step.waiting(barter)
          : state === BARTER_STEP_STATE.halted
            ? stoppedNote
            : null,
    };
  });
}

/**
 * COMO uma etapa terminou, quando ela podia terminar de mais de um jeito —
 * "Aprovada" ou "Negada" na decisão do comitê, `null` nas demais.
 *
 * A pergunta é sobre o estado ALCANÇADO pelo ato (o `toStatus` do evento), e não
 * sobre onde a permuta está hoje: a decisão de uma permuta já faturada continua
 * tendo sido uma aprovação, e é isso que a linha do tempo mostra.
 */
export function outcomeLabelOf(action: string, toStatus: string): string | null {
  const step = BARTER_STEPS[action as BarterAction];
  return step?.outcomes?.[toStatus as BarterStatus] ?? null;
}
