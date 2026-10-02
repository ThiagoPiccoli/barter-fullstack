import { normalizeName } from './product-name';

/**
 * Os CÓDIGOS do Barter — a identidade pública da safra da cultura e das suas
 * versões.
 *
 *   Safra   SOJA26/27       CANOLA2027        grão + anos da safra
 *   Versão  SOJA26/27.01    CANOLA2027.03     safra + sequência de dois dígitos
 *
 * O ANO tem duas formas, e quem escolhe é o admin ao abrir a safra: a cultura
 * que cruza o ano (planta num, colhe no outro) sai como `26/27`; a que cabe num
 * ano só sai como `2027`. Não há regra escondida por grão — o mesmo grão pode
 * ser de verão num ano e de inverno noutro.
 *
 * Cada código tem DUAS FORMAS. A com barra é a que se lê — no comprovante, na
 * CPR, na tela —, e é a que se grava em `code`. A barra não cabe numa URL, então
 * as rotas endereçam pelo `slug`, que é a mesma coisa sem ela (`SOJA2627.01`).
 */

/** O grão como entra no código: sem acento, sem espaço, em maiúsculas. */
function grainPart(grainName: string): string {
  return normalizeName(grainName)
    .replace(/[^a-z0-9]/g, '')
    .toUpperCase();
}

/** `26/27` na safra que cruza o ano; `2027` na que cabe num ano só. */
export function yearsLabel(startYear: number, endYear: number): string {
  if (startYear === endYear) return String(startYear);
  const short = (year: number) => String(year % 100).padStart(2, '0');
  return `${short(startYear)}/${short(endYear)}`;
}

/** Código da safra: `SOJA26/27`, `CANOLA2027`. */
export function seasonCode(grainName: string, startYear: number, endYear: number): string {
  return `${grainPart(grainName)}${yearsLabel(startYear, endYear)}`;
}

/** O nome que as pessoas leem: `Soja 26/27`, `Canola 2027`. */
export function seasonName(grainName: string, startYear: number, endYear: number): string {
  return `${grainName.trim()} ${yearsLabel(startYear, endYear)}`;
}

/** Código da versão: `SOJA26/27.01`, `SOJA26/27.02`… */
export function versionCode(season: string, number: number): string {
  return `${season}.${String(number).padStart(2, '0')}`;
}

/** A forma do código que vai na URL: a mesma, sem a barra. */
export function slugOf(code: string): string {
  return code.replace(/\//g, '');
}
