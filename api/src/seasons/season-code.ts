/**
 * Os CÓDIGOS do Barter — a identidade pública da safra e das suas versões.
 *
 *   Safra   B2026        letra do ciclo + ano
 *   Versão  B2026.01     safra + sequência de dois dígitos
 *
 * A letra ERA a inicial do grão ("S de soja"), e deixou de ser quando as
 * culturas passaram a coexistir dentro do lançamento (ver `VersionGrain`): uma
 * safra que aceita soja e milho não tem inicial. Hoje ela é a letra do CICLO, o
 * `B` de Barter por padrão, e continua editável — quem roda dois ciclos no mesmo
 * ano (verão e inverno) os separa por ela, que é a única coisa que o código
 * precisa distinguir.
 */

/** A letra do ciclo quando o admin não dita outra. */
export const DEFAULT_SEASON_LETTER = 'B';

/** Código da safra: `B2026`. */
export function seasonCode(letter: string, year: number): string {
  return `${letter.toUpperCase()}${year}`;
}

/** Código da versão: `B2026.01`, `B2026.02`… */
export function versionCode(season: string, number: number): string {
  return `${season}.${String(number).padStart(2, '0')}`;
}
