/**
 * Vigência e METAS de uma versão do Barter — sem I/O, para ser unit-testável.
 *
 * A versão tem duas coisas que parecem iguais e não são:
 *
 * - `endsAt` é uma DATA que o admin marcou. Ela trava: passada a data, a API
 *   recusa permuta nova. O admin decidiu com hora marcada, e um acordo fechado
 *   fora da vigência publicada não teria por que valer.
 * - as METAS (vendas, sacas, quantidade) MEDEM, e o efeito de batê-las é
 *   ESCOLHA de cada versão: `closeOnGoal` ligado encerra o Barter, desligado
 *   (o padrão) só acende o alerta no painel e deixa o encerramento para o admin.
 *
 * A escolha existe porque as duas leituras são legítimas e mudam por safra. Meta
 * é leitura de negócio: pode haver permuta na fila que muda a conta, e há
 * lançamento em que o admin quer olhar o realizado antes de desligar a
 * operação. Há também o oposto — a meta É o limite de crédito da safra, e
 * esperar um toque de alguém significa aprovar permuta além do que a
 * cooperativa se comprometeu a entregar.
 *
 * O QUE NÃO EXISTE, em nenhum dos dois modos, é rotina de madrugada. Quando o
 * automático está ligado, quem fecha a versão é a APROVAÇÃO que cruzou a meta —
 * ver `closeIfGoalReached` em seasons.service.ts. É o único instante em que o
 * realizado cresce (`COUNTS_AS_REALIZED`, abaixo), então o fechamento continua
 * tendo autor, hora e um ato humano por trás.
 *
 * Por isso `isOpenAt` segue olhando só data e status: no automático, o `status`
 * da versão JÁ está `closed` quando alguém pergunta se ela aceita permuta.
 */

import { BARTER_ACTION, lineFrom } from '../barters/barter-workflow';

/** Item já precificado de uma permuta (o snapshot do BarterItem). */
export interface CountedItem {
  kind: string;
  quantity: number;
  unitValue: number;
}

/** Uma permuta, reduzida ao que as metas precisam. */
export interface CountedBarter {
  status: string;
  items: CountedItem[];
}

/**
 * O realizado de uma versão, nas três unidades em que se pode pôr meta.
 *
 * Não há lucro. A lista de preços do fornecedor traz o preço de VENDA e mais
 * nada; sem custo, "lucro" seria o faturamento com outro nome — um número que
 * parece outro e engana quem lê o painel.
 */
export interface Realized {
  /** R$ em insumos retirados. */
  sales: number;
  /** Sacas do grão comprometidas. */
  sacks: number;
  /** Quantidade de permutas. */
  barters: number;
}

/** As metas da versão. `null` em qualquer uma = sem meta naquela unidade. */
export interface Targets {
  targetSales: number | null;
  targetSacks: number | null;
  targetBarters: number | null;
}

export const GOAL_KIND = {
  sales: 'sales',
  sacks: 'sacks',
  barters: 'barters',
} as const;

export type GoalKind = (typeof GOAL_KIND)[keyof typeof GOAL_KIND];

/** Uma meta definida, com o quanto dela já foi cumprido. */
export interface Goal {
  kind: GoalKind;
  target: number;
  realized: number;
  /** 0–1, saturado em 1 (a barra não passa do fim). */
  ratio: number;
  met: boolean;
}

const round2 = (value: number): number => Math.round(value * 100) / 100;

/**
 * O realizado das permutas DECIDIDAS A FAVOR — as aprovadas e as que já foram
 * faturadas. As que ainda esperam gerente ou comitê ficam de fora, e as negadas
 * também: meta é sobre negócio fechado, e contar o que ainda pode ser negado
 * faria a barra andar para trás na frente do admin.
 *
 * `invoiced` entra porque ela É uma aprovada — só que já faturada. Enquanto esta
 * conta olhava um estado só, a permuta SUMIA da meta no dia em que o faturista
 * emitia a nota: o negócio mais consolidado que existe zerava a barra.
 *
 * A lista vem da ESTEIRA, e não escrita à mão: "decidida a favor" é exatamente o
 * trecho da linha que o faturamento alcança (`lineFrom(invoice)`). Escrita à
 * mão, ela ficou para trás quando a decisão do comitê ganhou a terceira saída —
 * a permuta aprovada COM RESSALVA é negócio fechado e sumiria da meta sem que
 * ninguém percebesse. Ver `barters/barter-workflow.ts`.
 */
const COUNTS_AS_REALIZED: readonly string[] = lineFrom(BARTER_ACTION.invoice);

/**
 * Este estado soma na meta? É a mesma lista que a conta usa, exposta para quem
 * precisa saber se um ato MUDOU o realizado — o encerramento por meta pergunta
 * isso a cada decisão do comitê, e uma permuta negada não mexeu em nada.
 */
export function countsAsRealized(status: string): boolean {
  return COUNTS_AS_REALIZED.includes(status);
}

export function realizedFrom(barters: CountedBarter[]): Realized {
  const approved = barters.filter((barter) => COUNTS_AS_REALIZED.includes(barter.status));
  const inputs = approved.flatMap((barter) => barter.items.filter((item) => item.kind !== 'grain'));
  const sacks = approved
    .flatMap((barter) => barter.items.filter((item) => item.kind === 'grain'))
    .reduce((sum, item) => sum + item.quantity, 0);

  return {
    sales: round2(inputs.reduce((sum, item) => sum + item.quantity * item.unitValue, 0)),
    sacks: round2(sacks),
    barters: approved.length,
  };
}

/** As metas que existem, cruzadas com o realizado. Meta ausente não vira Goal. */
export function goalsOf(targets: Targets, realized: Realized): Goal[] {
  const pairs: [GoalKind, number | null, number][] = [
    [GOAL_KIND.sales, targets.targetSales, realized.sales],
    [GOAL_KIND.sacks, targets.targetSacks, realized.sacks],
    [GOAL_KIND.barters, targets.targetBarters, realized.barters],
  ];

  return pairs
    .filter(([, target]) => target !== null && target !== undefined && target > 0)
    .map(([kind, target, done]) => ({
      kind,
      target: target as number,
      realized: done,
      ratio: Math.min(done / (target as number), 1),
      met: done >= (target as number),
    }));
}

/** Alguma meta foi atingida? É o que acende o aviso "hora de encerrar". */
export function anyGoalMet(goals: Goal[]): boolean {
  return goals.some((goal) => goal.met);
}

/** Como cada meta se chama para quem lê — a trilha e o `closedBy` usam isto. */
export const GOAL_LABELS: Record<GoalKind, string> = {
  [GOAL_KIND.sales]: 'vendas',
  [GOAL_KIND.sacks]: 'sacas',
  [GOAL_KIND.barters]: 'permutas',
};

/**
 * A frase que explica um fechamento automático: qual meta bateu, e com quanto.
 *
 * Fica aqui, junto da conta, porque é o `closedBy` que a versão guarda para
 * sempre — e quem abre uma versão encerrada meses depois precisa saber POR QUE
 * ela fechou sem que ninguém tenha clicado em nada. `null` quando nenhuma meta
 * bateu: aí não há fechamento automático a explicar.
 *
 * Nomeia a PRIMEIRA meta batida, e não todas: duas metas cruzadas no mesmo
 * instante é o caso raro, e a frase longa atrapalharia o caso comum.
 */
export function closingReasonOf(goals: Goal[]): string | null {
  const met = goals.find((goal) => goal.met);
  if (!met) return null;
  const target = met.kind === GOAL_KIND.barters ? String(met.target) : met.target.toFixed(2);
  return `Automático: meta de ${GOAL_LABELS[met.kind]} atingida (${target})`;
}

/**
 * A versão aceita permuta neste instante? Ativa e dentro da vigência.
 *
 * `startsAt` no futuro também fecha: uma versão pode ser publicada hoje para
 * valer na segunda-feira, e até lá ninguém permuta por ela.
 */
export function isOpenAt(
  version: { status: string; startsAt: Date; endsAt: Date | null },
  now: Date,
): boolean {
  if (version.status !== 'active') return false;
  if (version.startsAt.getTime() > now.getTime()) return false;
  if (version.endsAt && version.endsAt.getTime() < now.getTime()) return false;
  return true;
}
