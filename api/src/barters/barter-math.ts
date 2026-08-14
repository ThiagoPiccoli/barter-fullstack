/**
 * Matemática pura da permuta — o coração do escambo, sem I/O, para ser
 * unit-testável e compartilhada entre validação e criação.
 *
 * Regra central do domínio: os INSUMOS retirados formam um custo (R$) e esse
 * custo é convertido em SACAS do grão de pagamento. Nunca o inverso.
 */

/** Tolerância de centavos ao comparar valores em R$ (mesma do app). */
export const MONEY_EPSILON = 0.01;

/** Um insumo escolhido, já precificado pelo servidor. */
export interface PricedInput {
  productId: number;
  quantity: number;
  unitPrice: number;
  classId: number | null;
}

/** Custo total dos insumos retirados (R$) — o valor que a permuta paga. */
export function inputCost(inputs: PricedInput[]): number {
  return inputs.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0);
}

/** Custo (R$) dos insumos que pertencem a uma classe. */
export function classSpend(inputs: PricedInput[], classId: number): number {
  return inputCost(inputs.filter((item) => item.classId === classId));
}

/**
 * Mínimo (R$) exigido pela regra de uma classe, dado o custo total da
 * permuta e a área (ha) do produtor. Retorna 0 quando não há exigência.
 */
export function classRequired(
  rule: { ruleType: string; ruleValue: number },
  context: { totalCost: number; areaHa: number },
): number {
  switch (rule.ruleType) {
    case 'percentOfTotal':
      return (context.totalCost * rule.ruleValue) / 100;
    case 'valuePerHa':
      return rule.ruleValue * context.areaHa;
    default:
      return 0;
  }
}

/**
 * Sacas do grão de pagamento necessárias para cobrir um custo. Arredondado a
 * 4 casas (precisão usada nos registros históricos do app).
 */
export function sacksToCover(cost: number, grainPrice: number): number {
  if (grainPrice <= 0) {
    return 0;
  }
  return Math.round((cost / grainPrice) * 10_000) / 10_000;
}

/**
 * Um item já fechado da permuta: quanto foi retirado, por qual preço e a que
 * custo. É a forma dos snapshots do BarterItem.
 */
export interface CostedItem {
  quantity: number;
  unitValue: number;
  unitCost: number;
}

/**
 * Margem (R$) dos insumos de uma permuta: (preço − custo) × quantidade.
 *
 * O custo vem congelado no item, não da tabela da versão: o lucro apurado de
 * uma permuta fechada não pode mudar porque alguém corrigiu um custo depois.
 * É esta conta que a meta de lucro do Barter acompanha.
 */
export function itemsProfit(items: CostedItem[]): number {
  const total = items.reduce(
    (sum, item) => sum + item.quantity * (item.unitValue - item.unitCost),
    0,
  );
  return Math.round(total * 100) / 100;
}

/**
 * Quantidade mínima obrigatória de um insumo para uma propriedade:
 * taxa por hectare × área, arredondada a 2 casas (regra do app).
 */
export function minQuantityFor(requiredPerHa: number, areaHa: number): number {
  if (requiredPerHa <= 0) {
    return 0;
  }
  return Math.round(requiredPerHa * areaHa * 100) / 100;
}
