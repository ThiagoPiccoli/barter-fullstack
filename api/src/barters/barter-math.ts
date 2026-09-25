/**
 * Matemática pura da permuta — o coração do escambo, sem I/O, para ser
 * unit-testável e compartilhada entre validação e criação.
 *
 * Regra central do domínio: os INSUMOS retirados formam um custo (R$) e esse
 * custo é convertido em SACAS do grão de pagamento. Nunca o inverso.
 */

/** Tolerância de centavos ao comparar valores em R$ (mesma do app). */
export const MONEY_EPSILON = 0.01;

/**
 * Tolerância (ha) ao comparar a área penhorada com a exigida — o `MONEY_EPSILON`
 * da terra.
 *
 * Ela existe pelo mesmo motivo do de centavos, e com um caso concreto: a área
 * exigida sai arredondada a duas casas e as lavouras são digitadas com duas
 * casas, então somas como `12,5 + 11,5` produzem `23,999999999999996` em ponto
 * flutuante. Sem a folga, o consultor que digitou exatamente a área pedida
 * levaria uma recusa por um centésimo de hectare que não existe — um metro
 * quadrado de discussão.
 */
export const AREA_EPSILON = 0.01;

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
 * Quantidade mínima obrigatória de um insumo para uma propriedade:
 * taxa por hectare × área, arredondada a 2 casas (regra do app).
 */
export function minQuantityFor(requiredPerHa: number, areaHa: number): number {
  if (requiredPerHa <= 0) {
    return 0;
  }
  return Math.round(requiredPerHa * areaHa * 100) / 100;
}

/**
 * Quantidade na precisão em que ela é GRAVADA (2 casas).
 *
 * Existia só no app (`roundQuantity`, em barter_math.dart), aplicada ao que o
 * consultor digita. O servidor aceitava o número como viesse — e é ele quem
 * grava. Quem chamasse a API direto, ou um app de versão diferente, registrava
 * `12,3456` de insumo: o item ficava assim no banco, a tela e o comprovante
 * mostravam `12,35`, e a conta impressa não fechava com a gravada.
 *
 * Duas casas porque é a precisão da unidade de venda — não se retira meio
 * milésimo de saco. E o arredondamento é o mesmo dos dois lados (ver o teste
 * de meio centavo em barter-math.spec.ts).
 */
export function roundQuantity(quantity: number): number {
  return Math.round(quantity * 100) / 100;
}

/**
 * A ÁREA DE LAVOURA (ha) que esta permuta precisa penhorar.
 *
 *     (sacas ÷ produtividade) × (1 + margem / 100)
 *
 * É a conversão que fecha o ciclo do escambo: o custo dos insumos vira sacas
 * (`sacksToCover`), e as sacas viram a terra que precisa produzi-las. A primeira
 * parte é a ÁREA ESTIMADA — o que a lavoura precisa ter se tudo correr bem; a
 * margem é a folga que a credora exige porque nem tudo corre bem.
 *
 * ARREDONDA PARA CIMA, e essa é a única decisão aqui que não é aritmética: este
 * número é o piso de uma GARANTIA. Arredondar 23,471 para 23,47 entrega um
 * milésimo de hectare de graça, e a direção do erro importa quando o que está do
 * outro lado é o que sobra se o produtor não entregar. Duas casas porque é a
 * precisão em que a área da matrícula é digitada (ver `CprArea.areaHa`) — pedir
 * um número mais fino do que o que se pode responder seria pedir o impossível.
 *
 * Zero quando não há sacas ou não há produtividade: não é "sem exigência", é
 * "não dá para calcular". Quem lê a ausência e decide o que ela significa é
 * `cprGapsOf` — aqui não se inventa uma área a partir de uma divisão por zero.
 */
export function pledgeAreaFor(sacks: number, yieldPerHa: number, marginPercent: number): number {
  if (!(sacks > 0) || !(yieldPerHa > 0)) {
    return 0;
  }
  const estimated = sacks / yieldPerHa;
  const required = estimated * (1 + Math.max(marginPercent, 0) / 100);
  // O recuo de 1e-9 antes do teto: sem ele, um `required` que deu 23,470000000001
  // por ponto flutuante viraria 23,48 — o arredondamento para cima inventando um
  // centésimo de hectare que a conta não pediu.
  return Math.ceil(required * 100 - 1e-9) / 100;
}
