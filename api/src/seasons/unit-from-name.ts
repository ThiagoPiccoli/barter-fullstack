/**
 * A EMBALAGEM que vem escondida na descrição do produto.
 *
 * A lista de preços do fornecedor não tem coluna de unidade: ela vem no fim do
 * nome — `HERBIC.AMINOL 806 emb.20 l`, `HERBIC.ZARTAN 200GR`,
 * `GLIF.720WG NORTOX 5KG`. Sem isto, todo item entraria como "unidade", e o
 * consultor pediria "3 unidades" de um produto que se compra em bombona de 20
 * litros.
 *
 * Duas decisões que fazem a leitura ser confiável em vez de esperta:
 *
 * 1. **Vale a ÚLTIMA medida do nome.** As primeiras costumam ser concentração
 *    do princípio ativo (`SC630`, `WP-500 G/KG`, `480 SL`); a embalagem é o que
 *    fecha a descrição.
 * 2. **Medida seguida de barra é concentração, não embalagem** (`100g/L`,
 *    `500 G/KG`). Essa é a regra que evita cadastrar um herbicida "de 100 g"
 *    quando ele vem em bombona.
 *
 * Não achando medida nenhuma, cai para o padrão da CLASSE (fertilizante a peso
 * é tonelada) — e, se nem isso resolver, devolve null. Null é sinal, não
 * desistência: quem chama marca o item para o admin escrever a unidade depois,
 * porque unidade chutada vai parar no comprovante do produtor.
 */

/** Como cada sufixo do fornecedor é escrito no cadastro. */
const UNITS: Record<string, string> = {
  l: 'L',
  lt: 'L',
  lts: 'L',
  litro: 'L',
  litros: 'L',
  ml: 'mL',
  kg: 'kg',
  kgs: 'kg',
  quilo: 'kg',
  quilos: 'kg',
  g: 'g',
  gr: 'g',
  grs: 'g',
  grama: 'g',
  gramas: 'g',
  t: 't',
  ton: 't',
  tonelada: 't',
  ds: 'ds',
  doses: 'ds',
};

const MEASURE = new RegExp(
  // número (com vírgula ou ponto) + espaço opcional + sufixo de unidade,
  // desde que o sufixo não seja seguido de "/" (aí é concentração).
  String.raw`(\d+(?:[.,]\d+)?)\s*(${Object.keys(UNITS).join('|')})(?![a-z0-9/])`,
  'gi',
);

/** Quantidade sem zero à esquerda e sem decimal inútil: `05` → `5`, `2,5` → `2,5`. */
function tidyQuantity(raw: string): string {
  const normalized = raw.replace(',', '.');
  const value = Number.parseFloat(normalized);
  if (!Number.isFinite(value)) return raw;
  return value === Math.trunc(value) ? String(Math.trunc(value)) : String(value).replace('.', ',');
}

/**
 * Embalagens que o fornecedor escreve por extenso, sem número: o adubo não vem
 * em "20 L", vem em big-bag ou a granel. São 98 itens da lista real — todos
 * fertilizantes —, e sem isto todos eles entrariam como "unidade".
 *
 * `BB`, `B-B` e `B-BAG` são a mesma coisa que `BIG-BAG`: quem digita a lista
 * abrevia, e o cadastro não deveria herdar a abreviação de cada dia.
 */
const PACKAGES: [RegExp, string][] = [
  [/\bbig[\s.-]?bag\b|\bb[\s.-]?bag\b|\bb[\s.-]?b\b|\bbb\b|\bbag\b/i, 'big-bag'],
  [/\bmist\b|\bmistura\b|\bgranel\b/i, 'granel'],
];

/**
 * Padrão por CLASSE, para o que o nome não diz.
 *
 * Fertilizante sem embalagem no nome (`UREIA PLUS (45-00-00)`, `DAP 18-46-00`,
 * `CLORETO DE POTASSIO`) é vendido a peso, por tonelada — e o preço confirma:
 * esses itens estão na mesma faixa dos que vêm em big-bag (R$ 2.590 a 8.000),
 * e um big-bag É uma tonelada. Não é chute: é a leitura de uma classe inteira,
 * conferida contra os 656 itens da lista real.
 *
 * Classe que não estiver aqui devolve null de propósito — o item é marcado
 * para revisão em vez de receber uma unidade inventada.
 */
const UNIT_BY_CLASS: Record<string, string> = {
  fertilizantes: 'tonelada',
};

/** Nome de classe comparável: sem acento, sem caixa, sem espaço repetido. */
function normalizeClass(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * A unidade lida da descrição (`20 L`, `10 kg`, `big-bag`), ou null quando o
 * nome não diz a embalagem.
 *
 * A medida numérica vem primeiro: `ADUBO 12-15-12 ... BIG-BAG` é big-bag, mas
 * `FERTILIZ. TRANSLOK 10KG` é 10 kg mesmo tendo "BAG" em outro item da lista.
 */
export function unitFromName(description: string): string | null {
  const matches = [...description.matchAll(MEASURE)];
  if (matches.length > 0) {
    const [, quantity, suffix] = matches[matches.length - 1];
    const unit = UNITS[suffix.toLowerCase()];
    if (unit) return `${tidyQuantity(quantity)} ${unit}`;
  }

  for (const [pattern, unit] of PACKAGES) {
    if (pattern.test(description)) return unit;
  }
  return null;
}

/**
 * A unidade de um item da planilha: o que o nome diz e, quando ele não diz
 * nada, o padrão da classe. Null significa "não deu para saber" — e é isso que
 * marca o item para o admin escrever depois.
 */
export function unitFor(row: { name: string; productClass: string | null }): string | null {
  return (
    unitFromName(row.name) ??
    (row.productClass ? (UNIT_BY_CLASS[normalizeClass(row.productClass)] ?? null) : null)
  );
}
