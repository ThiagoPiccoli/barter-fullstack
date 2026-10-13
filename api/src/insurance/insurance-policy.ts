/**
 * A POLÍTICA DE SEGURO de uma versão do Barter, e a ESCOLHA que ela produz em
 * cada permuta — sem I/O, para ser unit-testável.
 *
 * A política é do ADMIN, por versão (com um padrão por safra, ver
 * `Season.insurancePolicy`):
 *
 * - `required`: toda permuta leva seguro, e o município sem taxa recusa o
 *   registro;
 * - `optional`: o consultor decide com o produtor, permuta a permuta — e o
 *   município sem taxa só deixa a opção bloqueada;
 * - `none`: a versão não oferece seguro.
 *
 * A escolha é o que ficou gravado na permuta (`Barter.insuranceChoice`), e ela
 * tem QUATRO valores porque "sem seguro" passou a ter duas histórias: a versão
 * não oferecia, ou o produtor recusou. As duas pesam diferente na mesa do comitê.
 */

export const INSURANCE_POLICY = {
  required: 'required',
  optional: 'optional',
  none: 'none',
} as const;

export type InsurancePolicy = (typeof INSURANCE_POLICY)[keyof typeof INSURANCE_POLICY];

export const INSURANCE_POLICIES: readonly InsurancePolicy[] = Object.values(INSURANCE_POLICY);

export const INSURANCE_POLICY_MESSAGE = `A política de seguro deve ser ${INSURANCE_POLICIES.join(', ')}`;

/** Como cada política se diz para quem lê — a trilha usa isto. */
export const INSURANCE_POLICY_LABELS: Record<InsurancePolicy, string> = {
  required: 'seguro obrigatório',
  optional: 'seguro opcional',
  none: 'sem seguro',
};

export const INSURANCE_CHOICE = {
  /** A versão obrigava. */
  required: 'required',
  /** Era opcional, e o produtor quis. */
  accepted: 'accepted',
  /** Era opcional, e o produtor recusou. */
  declined: 'declined',
  /** A versão não oferecia. */
  none: 'none',
} as const;

export type InsuranceChoice = (typeof INSURANCE_CHOICE)[keyof typeof INSURANCE_CHOICE];

/** A escolha leva seguro? É o que decide se a permuta ganha a linha. */
export function choiceInsures(choice: InsuranceChoice): boolean {
  return choice === INSURANCE_CHOICE.required || choice === INSURANCE_CHOICE.accepted;
}

/**
 * A ESCOLHA desta permuta, dada a política da versão e o que o consultor pediu —
 * ou a frase que recusa o pedido.
 *
 * `wanted` é o que veio da tela: `true`/`false` quando o seguro é opcional, e
 * `undefined` quando o consultor não disse nada (o caso normal fora do opcional).
 *
 * O pedido que CONTRADIZ a política é recusado, e não ignorado: um "com seguro"
 * numa versão sem seguro, atendido em silêncio, sairia sem a linha que o
 * consultor prometeu ao produtor — e o oposto, "sem seguro" numa versão que
 * obriga, sairia com uma linha que ele disse que não viria.
 *
 * No OPCIONAL, o silêncio é recusa: seguro é custo, e custo não entra numa
 * permuta sem que alguém tenha dito que entra.
 */
export function insuranceChoiceFor(
  policy: string,
  wanted: boolean | undefined,
): { choice: InsuranceChoice } | { refusal: string } {
  switch (policy) {
    case INSURANCE_POLICY.required:
      if (wanted === false) {
        return { refusal: 'O seguro agrícola é obrigatório neste Barter e não pode ser retirado' };
      }
      return { choice: INSURANCE_CHOICE.required };
    case INSURANCE_POLICY.optional:
      return { choice: wanted ? INSURANCE_CHOICE.accepted : INSURANCE_CHOICE.declined };
    default:
      if (wanted === true) {
        return { refusal: 'Este Barter não oferece seguro agrícola' };
      }
      return { choice: INSURANCE_CHOICE.none };
  }
}
