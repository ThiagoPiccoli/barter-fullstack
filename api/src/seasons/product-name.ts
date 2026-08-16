/**
 * A forma COMPARÁVEL do nome de um produto ou de uma classe — em um lugar só.
 *
 * Isto vive fora do version-import.ts e do seasons.service.ts porque os dois
 * precisam concordar, e já não concordaram. A leitura da planilha recusava
 * linha repetida comparando `nome.toLowerCase()`; o casamento com o catálogo,
 * logo depois, procurava o produto por nome SEM ACENTO e com espaços
 * colapsados. Duas grafias do mesmo item — `Ureia 45%` e `Uréia  45%` —
 * passavam pela primeira conferência como produtos diferentes e chegavam na
 * segunda como o mesmo, gerando duas linhas de preço para um produto só.
 *
 * Quem barrava aquilo era o índice único `[versionId, productId]`, com um
 * P2002 que vira "Já existe um registro com estes dados." — sem número de
 * linha, sobre um arquivo que o leitor tinha acabado de aprovar, e depois de
 * os produtos já terem sido criados. A mensagem com o número da linha existe
 * exatamente para esse caso; ela só não era alcançada.
 */

/** Nome comparável: sem acento, sem caixa e sem espaço repetido. */
export function normalizeName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/** `FERTILIZANTES FOLIARES` → `fertilizantes-foliares`. */
export function slugify(value: string): string {
  return normalizeName(value).replace(/\s+/g, '-');
}
