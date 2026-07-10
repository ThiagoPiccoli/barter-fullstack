/**
 * Matemática pura da permuta — o coração do escambo, sem I/O, para ser
 * unit-testável e compartilhada entre validação e criação.
 *
 * Regra central do domínio: os INSUMOS retirados formam um custo (R$) e esse
 * custo é convertido em SACAS do grão de pagamento. Nunca o inverso.
 */

/** Tolerância de centavos ao comparar valores em R$ (mesma do app). */
export const MONEY_EPSILON = 0.01

/** Um insumo escolhido, já precificado pelo servidor. */
export interface PricedInput {
  productId: number
  quantity: number
  unitPrice: number
  categoryId: number | null
}

/** Custo total dos insumos retirados (R$) — o valor que a permuta paga. */
export function inputCost(inputs: PricedInput[]): number {
  return inputs.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0)
}

/** Custo (R$) dos insumos que pertencem a uma categoria. */
export function categorySpend(inputs: PricedInput[], categoryId: number): number {
  return inputCost(inputs.filter((item) => item.categoryId === categoryId))
}

/**
 * Mínimo (R$) exigido por uma regra de categoria, dado o custo total da
 * permuta e a área (ha) do produtor. Retorna 0 quando não há exigência.
 */
export function categoryRequired(
  rule: { ruleType: 'none' | 'percentOfTotal' | 'valuePerHa'; ruleValue: number },
  context: { totalCost: number; areaHa: number }
): number {
  switch (rule.ruleType) {
    case 'percentOfTotal':
      return (context.totalCost * rule.ruleValue) / 100
    case 'valuePerHa':
      return rule.ruleValue * context.areaHa
    case 'none':
      return 0
  }
}

/**
 * Sacas do grão de pagamento necessárias para cobrir um custo. Arredondado a
 * 4 casas (precisão usada nos registros históricos do app).
 */
export function sacksToCover(cost: number, grainPrice: number): number {
  if (grainPrice <= 0) {
    return 0
  }
  return Math.round((cost / grainPrice) * 10_000) / 10_000
}

/**
 * Quantidade mínima obrigatória de um insumo para uma propriedade:
 * taxa por hectare × área, arredondada a 2 casas (regra do app).
 */
export function minQuantityFor(requiredPerHa: number, areaHa: number): number {
  if (requiredPerHa <= 0) {
    return 0
  }
  return Math.round(requiredPerHa * areaHa * 100) / 100
}
