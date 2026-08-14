/**
 * Vigência e METAS de uma versão do Barter — sem I/O, para ser unit-testável.
 *
 * A versão tem duas coisas que parecem iguais e não são:
 *
 * - `endsAt` é uma DATA que o admin marcou. Ela trava: passada a data, a API
 *   recusa permuta nova. O admin decidiu com hora marcada, e um acordo fechado
 *   fora da vigência publicada não teria por que valer.
 * - as METAS (vendas, lucro, sacas, quantidade) apenas MEDEM. Atingir a meta
 *   acende o alerta no painel; quem encerra é o admin. Nada fecha sozinho de
 *   madrugada, porque o realizado é uma leitura de negócio — pode haver uma
 *   permuta na fila que muda a conta, e desligar a operação por conta própria é
 *   pior do que avisar.
 *
 * Se um dia a meta precisar travar como a data, o lugar é `isOpenAt`.
 */

import { itemsProfit } from '../barters/barter-math';

/** Item já precificado E custeado de uma permuta (o snapshot do BarterItem). */
export interface CountedItem {
  kind: string;
  quantity: number;
  unitValue: number;
  unitCost: number;
}

/** Uma permuta, reduzida ao que as metas precisam. */
export interface CountedBarter {
  status: string;
  items: CountedItem[];
}

/** O realizado de uma versão, nas quatro unidades em que se pode pôr meta. */
export interface Realized {
  /** R$ em insumos retirados. */
  sales: number;
  /** R$ de margem: (preço − custo) × quantidade dos insumos. */
  profit: number;
  /** Sacas do grão comprometidas. */
  sacks: number;
  /** Quantidade de permutas. */
  barters: number;
}

/** As metas da versão. `null` em qualquer uma = sem meta naquela unidade. */
export interface Targets {
  targetSales: number | null;
  targetProfit: number | null;
  targetSacks: number | null;
  targetBarters: number | null;
}

export const GOAL_KIND = {
  sales: 'sales',
  profit: 'profit',
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
 * O realizado das permutas APROVADAS. Pendentes e negadas ficam de fora de
 * propósito: meta é sobre negócio fechado — contar o que ainda pode ser negado
 * faria a barra andar para trás na frente do admin.
 */
export function realizedFrom(barters: CountedBarter[]): Realized {
  const approved = barters.filter((barter) => barter.status === 'approved');
  const inputs = approved.flatMap((barter) => barter.items.filter((item) => item.kind !== 'grain'));
  const sacks = approved
    .flatMap((barter) => barter.items.filter((item) => item.kind === 'grain'))
    .reduce((sum, item) => sum + item.quantity, 0);

  return {
    sales: round2(inputs.reduce((sum, item) => sum + item.quantity * item.unitValue, 0)),
    profit: itemsProfit(inputs),
    sacks: round2(sacks),
    barters: approved.length,
  };
}

/** As metas que existem, cruzadas com o realizado. Meta ausente não vira Goal. */
export function goalsOf(targets: Targets, realized: Realized): Goal[] {
  const pairs: [GoalKind, number | null, number][] = [
    [GOAL_KIND.sales, targets.targetSales, realized.sales],
    [GOAL_KIND.profit, targets.targetProfit, realized.profit],
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
