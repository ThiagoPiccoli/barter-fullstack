/**
 * Os CÓDIGOS do Barter — a identidade pública da safra e das suas versões.
 *
 *   Safra   S2026        letra do grão + ano
 *   Versão  S2026.01     safra + sequência de dois dígitos
 *22
 * A letra do grão é o que faz o código ser lido de bate-pronto ("S de soja"),
 * e por isso ela é sugerida a partir do nome mas pode ser DITADA pelo admin:
 * soja e sorgo começam com a mesma letra, e quem resolve o empate é quem
 * conhece a operação, não uma regra de desempate inventada aqui.
 */

/** Sugestão de letra para um grão: a primeira, sem acento e em maiúscula. */
export function letterFor(grainName: string): string {
  const normalized = grainName
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z]/g, '');
  return normalized.slice(0, 1).toUpperCase() || 'X';
}

/** Código da safra: `S2026`. */
export function seasonCode(letter: string, year: number): string {
  return `${letter.toUpperCase()}${year}`;
}

/** Código da versão: `S2026.01`, `S2026.02`… */
export function versionCode(season: string, number: number): string {
  return `${season}.${String(number).padStart(2, '0')}`;
}
