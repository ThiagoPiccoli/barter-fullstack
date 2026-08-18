/**
 * O IMPOSTO DA ENTREGA — Funrural e Senar sobre a permuta.
 *
 * A entrega de grão é COMERCIALIZAÇÃO DE PRODUÇÃO RURAL, e é sobre ela que
 * incidem a contribuição previdenciária rural (o "Funrural") e a contribuição
 * ao Senar. A permuta não é exceção: o produtor paga os insumos entregando
 * grão, e essa entrega é uma venda como qualquer outra.
 *
 * O que se ESCOLHE no fechamento da permuta são as duas formas de recolhimento
 * da parte previdenciária:
 *
 * - `comercializacao` — a base é a receita bruta da venda. É o padrão e o caso
 *   da esmagadora maioria: quem não faz a opção formal cai aqui.
 * - `folha` — a base é a FOLHA DE PAGAMENTO (20% de INSS patronal + RAT,
 *   ~23% no total). Compensa para quem fatura muito com pouca gente empregada.
 *
 * O que NÃO se escolhe é o Senar: ele incide sobre a receita bruta da
 * comercialização SEMPRE, inclusive para quem optou pela folha. É por isso que
 * `folha` não zera a conta desta permuta — ela reduz o percentual ao Senar, e é
 * exatamente essa diferença que a tela precisa mostrar.
 *
 * PF ou PJ não é pergunta: sai do documento do produtor da permuta (11 dígitos
 * = CPF, 14 = CNPJ, ver `producers/document.ts`). Perguntar de novo criaria a
 * chance de o cadastro dizer CPF e o imposto ser calculado como PJ.
 *
 * As alíquotas abaixo são as vigentes desde 1º/04/2026 (LC 224/2025). O que
 * decide qual delas vale é a DATA DA COMERCIALIZAÇÃO, não a da safra — por isso
 * a permuta grava a alíquota que aplicou (ver `Barter.taxRate` no schema), em
 * vez de recalculá-la na leitura: um comprovante emitido depois da lei seguinte
 * não pode passar a mostrar outro número.
 */

/** As duas formas de recolhimento da contribuição previdenciária rural. */
export const TAX_REGIME = {
  /** Sobre a receita bruta da comercialização. O padrão. */
  comercializacao: 'comercializacao',
  /** Sobre a folha de pagamento — mas o Senar continua sobre a receita. */
  folha: 'folha',
} as const;

export type TaxRegime = (typeof TAX_REGIME)[keyof typeof TAX_REGIME];

export const TAX_REGIMES = Object.values(TAX_REGIME) as TaxRegime[];

export const TAX_REGIME_MESSAGE =
  'O regime de recolhimento é "comercializacao" (sobre a receita) ou "folha" (sobre a folha de pagamento)';

export function isTaxRegime(value: unknown): value is TaxRegime {
  return typeof value === 'string' && (TAX_REGIMES as string[]).includes(value);
}

/**
 * A COMPOSIÇÃO da alíquota sobre a comercialização, por tipo de pessoa.
 *
 * Ficam separadas em parcelas, e não como um total só, porque é a separação que
 * o regime `folha` usa: lá a previdência e o RAT saem da receita (vão para a
 * folha) e o Senar fica. Um único número obrigaria a manter duas tabelas
 * inteiras que só coincidem em uma linha.
 */
const RATES = {
  /** Produtor pessoa física (CPF): 1,32 + 0,11 + 0,20 = 1,63%. */
  pf: { previdencia: 1.32, rat: 0.11, senar: 0.2 },
  /** Produtor pessoa jurídica (CNPJ): 1,98 (Funrural + RAT) + 0,25 = 2,23%. */
  pj: { previdencia: 1.98, rat: 0, senar: 0.25 },
} as const;

export type TaxPayerKind = keyof typeof RATES;

/** CPF (11 dígitos) é pessoa física; CNPJ (14), jurídica. */
export function taxPayerKindOf(documentDigits: string): TaxPayerKind {
  return documentDigits.length === 14 ? 'pj' : 'pf';
}

/**
 * A alíquota (%) que incide sobre o valor da entrega de grão.
 *
 * No regime `folha` sobra só o Senar: a parte previdenciária existe, mas a base
 * dela é a folha de pagamento do produtor — que este sistema não conhece e não
 * tem por que conhecer. Devolver a alíquota cheia ali seria cobrar duas vezes
 * do mesmo produtor no papel.
 */
export function taxRateOf(regime: TaxRegime, documentDigits: string): number {
  const rate = RATES[taxPayerKindOf(documentDigits)];
  const total = regime === TAX_REGIME.folha ? rate.senar : rate.previdencia + rate.rat + rate.senar;
  // Duas casas: as alíquotas são publicadas assim, e somar 1.32 + 0.11 + 0.2 em
  // ponto flutuante devolve 1.6300000000000001 — que viraria um comprovante
  // com dezesseis casas de imposto.
  return Math.round(total * 100) / 100;
}

/**
 * O valor devido, dado o valor da comercialização (R$) e a alíquota (%).
 *
 * Arredonda em CENTAVOS, e só no fim: é dinheiro, e a conta de quem confere é
 * "valor × alíquota", uma vez só.
 */
export function taxAmountOf(commercializedValue: number, rate: number): number {
  if (commercializedValue <= 0 || rate <= 0) return 0;
  return Math.round(commercializedValue * rate) / 100;
}
