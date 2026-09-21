import { parseNumber } from '../seasons/version-import';
import { sameCity } from './insurance-rate';

/**
 * A PLANILHA da seguradora — município e quanto custa segurar um hectare nele.
 *
 * A cotação chega à empresa como chegou a tabela do fornecedor: um arquivo com
 * centenas de linhas, uma por praça. Digitá-las seria transcrever a planilha da
 * seguradora — e a linha 214 sai com um dígito trocado num valor que multiplica
 * mil hectares.
 *
 * A separação é a mesma de `version-import.ts`, e de propósito:
 *
 *   readWorkbook(buffer) → string[][]              (a parte que conhece xlsx)
 *   parseInsuranceSheet(string[][]) → ImportResult (a regra, testável sem arquivo)
 *
 * ## A planilha real tem TRÊS valores por hectare
 *
 * E essa é a decisão que este leitor toma, porque o arquivo não a toma:
 *
 * | coluna                          | o que é                                    |
 * |---------------------------------|--------------------------------------------|
 * | `SEM Subvenção (R$/ha)`         | o prêmio cheio                              |
 * | `COM Subvenção (R$/ha)`         | o prêmio com a subvenção federal aplicada   |
 * | `Reajuste para Safra … + x%`    | o prêmio com subvenção E o custo financeiro |
 *
 * A ÚLTIMA é a que a permuta cobra, e ela é escolhida primeiro: é o valor que a
 * empresa de fato adianta ao produtor — a subvenção já entrou (na planilha real,
 * ela é o valor com subvenção multiplicado por um fator fixo, linha a linha,
 * inclusive nas praças em que há subvenção e nas em que não há), e o custo
 * financeiro da safra também. Cobrar a coluna "SEM Subvenção" de um produtor de
 * praça subvencionada seria cobrar dele um dinheiro que o governo pagou.
 *
 * Quem lê o arquivo recebe de volta QUAL COLUNA foi usada (ver `priceColumn`), e
 * isso não é enfeite: é a única maneira de o admin perceber, no mesmo minuto em
 * que carregou, que a planilha deste ano veio com os títulos trocados. A escolha
 * também pode ser forçada (`preferredColumn`), para o dia em que a diretoria
 * decidir cobrar outra.
 *
 * ## O que mais a planilha traz
 *
 * Seguradora, nível de cobertura, valor segurado e se a praça tem subvenção não
 * viram colunas do cadastro — viram a OBSERVAÇÃO da praça. Elas não participam
 * de conta nenhuma (o que a permuta usa é um número por hectare), mas são o que
 * o admin confere quando o produtor pergunta "por que a minha praça é mais
 * cara?". Guardá-las como campos seria cadastrar a planilha inteira para nunca
 * consultá-la; jogá-las fora seria perder a resposta.
 *
 * Erro é reportado POR LINHA, e qualquer um recusa o arquivo inteiro — mesma
 * escolha da tabela de valores. Meia base publicada é pior do que nenhuma: as
 * praças que ficaram de fora recusam permuta, e ninguém percebe até um consultor
 * esbarrar nisso com o produtor na frente.
 */

/** Uma linha válida da planilha de seguros. */
export interface InsuranceImportRow {
  /** Número da linha na planilha — é o que o admin procura para corrigir. */
  line: number;
  city: string;
  valuePerHa: number;
  note: string | null;
}

export interface InsuranceImportResult {
  rows: InsuranceImportRow[];
  errors: string[];
  /**
   * A coluna de onde o valor saiu, como ela estava escrita no arquivo, e o nome
   * curto dela. `null` quando não houve leitura (o cabeçalho não foi achado).
   */
  priceColumn: { id: PriceColumnId; label: string; header: string } | null;
  /**
   * Quantas linhas foram IGNORADAS por serem enfeite de planilha — a linha
   * "Selecione o Município", com todos os números zerados, que existe para o
   * seletor da própria planilha e não é praça nenhuma.
   */
  ignored: number;
}

/**
 * AS COLUNAS DE PREÇO que o leitor conhece, na ordem em que ele as prefere.
 *
 * `match` é PREFIXO, e não igualdade, por causa do título que muda todo ano:
 * "Reajuste para Safra (maio/26) + 1,5% financeiro" vira
 * "reajustesafra15financeiro" depois de normalizado, e no ano que vem vira
 * outra coisa. O que não muda é o começo.
 *
 * A ORDEM é a regra de negócio: o valor que a empresa adianta primeiro, o
 * prêmio subvencionado depois, o cheio por último, e os títulos genéricos
 * ("valor por hectare") no fim — são os da planilha feita à mão pelo
 * escritório, que só tem uma coluna de valor.
 */
const PRICE_COLUMNS = [
  {
    id: 'reajuste',
    label: 'reajuste para a safra',
    match: (header: string) => header.startsWith('reajuste'),
  },
  {
    id: 'comSubvencao',
    label: 'prêmio com subvenção',
    match: (header: string) => header.startsWith('comsubvencao'),
  },
  {
    id: 'semSubvencao',
    label: 'prêmio sem subvenção',
    match: (header: string) => header.startsWith('semsubvencao'),
  },
  {
    id: 'generica',
    label: 'valor por hectare',
    match: (header: string) =>
      [
        'valor',
        'valorha',
        'valorporha',
        'valorhectare',
        'valorporhectare',
        'rsha',
        'rsporha',
        'preco',
        'precoha',
        'precoporha',
        'custo',
        'custoha',
        'custoporha',
        'custoporhectare',
        'premio',
        'premioha',
        'premioporha',
        'taxa',
        'taxaha',
        'taxaporha',
      ].includes(header),
  },
] as const;

export type PriceColumnId = (typeof PRICE_COLUMNS)[number]['id'];

/** Os identificadores das colunas de preço — o que o DTO aceita como escolha. */
export const PRICE_COLUMN_IDS = PRICE_COLUMNS.map((column) => column.id);

/**
 * As colunas que o leitor reconhece além do preço.
 *
 * `city` é a única obrigatória junto com o valor. As demais são CONTEXTO: elas
 * não entram em conta nenhuma, e viram a observação da praça (ver
 * `noteFrom`).
 */
const COLUMNS = {
  city: ['municipio', 'cidade', 'praca', 'local', 'localidade', 'municipiouf'],
  insurer: ['seguradora', 'seguro', 'cia', 'companhia'],
  subsidy: ['subvencao', 'subvencaofederal'],
  coverage: ['niveldecobertura', 'cobertura', 'nivelcobertura'],
  insuredValue: ['valorsegurado', 'importanciasegurada', 'capitalsegurado'],
  note: ['observacao', 'obs', 'nota', 'detalhe', 'comentario'],
} as const;

type ColumnKey = keyof typeof COLUMNS;

/**
 * Cabeçalho reduzido à forma comparável — a mesma função do outro leitor, e
 * pelo mesmo motivo: a planilha real traz `Valor por hectare (R$)`, e sem tirar
 * o que está entre parênteses sobra um "r" grudado no fim.
 *
 * O que está entre PARÊNTESES cai fora, e isso é o que faz "SEM Subvenção
 * (R$/ha)" e "COM Subvenção (R$/ha)" serem distinguíveis de verdade: sem isso,
 * as duas terminariam com o mesmo "rsha" no fim e a diferença entre elas ficaria
 * dependendo de qual aparece primeiro.
 */
function normalizeHeader(value: string): string {
  return value
    .replace(/\([^)]*\)/g, '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

/** Onde cada coluna de contexto caiu, a partir da linha de cabeçalho. */
function mapColumns(header: string[]): Partial<Record<ColumnKey, number>> {
  const found: Partial<Record<ColumnKey, number>> = {};
  header.forEach((cell, index) => {
    const normalized = normalizeHeader(cell);
    if (!normalized) return;
    for (const [key, aliases] of Object.entries(COLUMNS) as [ColumnKey, readonly string[]][]) {
      if (found[key] === undefined && aliases.includes(normalized)) {
        found[key] = index;
      }
    }
  });
  return found;
}

/**
 * A COLUNA DE PREÇO desta planilha — a primeira da ordem de preferência que
 * estiver nela, ou a que o admin pediu.
 *
 * `preferred` que não existe no arquivo NÃO cai para a seguinte em silêncio: a
 * escolha é do admin, e trocá-la por conta própria produziria uma base inteira
 * cobrando outro número sem ninguém ter decidido isso. Quem avisa é o
 * `parseInsuranceSheet`, com o erro que lista as colunas que existem.
 */
function findPriceColumn(
  header: string[],
  preferred?: PriceColumnId,
): { id: PriceColumnId; label: string; header: string; index: number } | null {
  const candidates = preferred
    ? PRICE_COLUMNS.filter((column) => column.id === preferred)
    : PRICE_COLUMNS;

  for (const column of candidates) {
    const index = header.findIndex((cell) => {
      const normalized = normalizeHeader(cell);
      return normalized !== '' && column.match(normalized);
    });
    if (index >= 0) {
      return { id: column.id, label: column.label, header: header[index].trim(), index };
    }
  }
  return null;
}

/**
 * Acha a linha de cabeçalho. Não assumimos que seja a primeira: planilha de
 * seguradora costuma abrir com o nome da empresa e a data da cotação.
 */
function findHeader(matrix: string[][], preferred?: PriceColumnId): number {
  for (let index = 0; index < Math.min(matrix.length, 20); index++) {
    const columns = mapColumns(matrix[index]);
    if (columns.city !== undefined && findPriceColumn(matrix[index], preferred)) return index;
  }
  return -1;
}

/**
 * QUANTAS PRAÇAS a base aceita de uma vez.
 *
 * O Brasil tem 5.570 municípios, e este teto é generoso sobre o total: uma
 * empresa opera em dezenas de praças, e uma planilha maior do que o país é
 * arquivo errado, não base grande. Quem recusa o exagero antes disto são os
 * tetos de células do leitor de xlsx.
 */
export const MAX_INSURANCE_RATES = 6_000;

/** A planilha (já como matriz de texto) virando linhas conferidas. */
export function parseInsuranceSheet(
  matrix: string[][],
  preferredColumn?: PriceColumnId,
): InsuranceImportResult {
  const headerIndex = findHeader(matrix, preferredColumn);
  if (headerIndex === -1) {
    return {
      rows: [],
      errors: [
        preferredColumn
          ? `Não encontrei a coluna de valor que você escolheu ("${
              PRICE_COLUMNS.find((column) => column.id === preferredColumn)?.label ??
              preferredColumn
            }") junto com a coluna do município.`
          : 'Não encontrei o cabeçalho da tabela. A planilha precisa de uma linha com a coluna ' +
            '"município" e uma coluna de valor por hectare — "Reajuste para Safra", ' +
            '"COM Subvenção", "SEM Subvenção" ou "Valor por hectare".',
      ],
      priceColumn: null,
      ignored: 0,
    };
  }

  const header = matrix[headerIndex];
  const columns = mapColumns(header);
  const price = findPriceColumn(header, preferredColumn)!;
  const rows: InsuranceImportRow[] = [];
  const errors: string[] = [];
  let ignored = 0;

  /**
   * O que já apareceu, e a linha em que apareceu.
   *
   * A comparação é por `sameCity`, e não pela chave crua, porque a repetição
   * que acontece de verdade é a do MESMO município escrito de dois jeitos —
   * "TUPANCIRETÃ" numa linha e "Tupanciretã/RS" em outra. As duas iriam para a
   * base como praças diferentes, e a permuta passaria a achar duas taxas para o
   * produtor: a recusa aqui é o que impede a ambiguidade de nascer.
   */
  const seen: { city: string; line: number }[] = [];

  const at = (row: string[], key: ColumnKey): string => {
    const index = columns[key];
    return index === undefined ? '' : (row[index] ?? '').trim();
  };

  for (let index = headerIndex + 1; index < matrix.length; index++) {
    const row = matrix[index];
    const line = index + 1;
    if (row.every((cell) => !cell || !cell.trim())) continue;

    const city = at(row, 'city');
    const valueText = (row[price.index] ?? '').trim();
    // Rodapé ("Cotação válida até…") entra como linha só com texto na primeira
    // coluna: sem praça e sem valor, não é linha de base — é ruído.
    if (!city && !valueText) continue;

    // A LINHA DE ENFEITE: "Selecione o Município", com todos os números
    // zerados. Ela é o seletor da planilha do escritório — existe para a
    // fórmula de lá, e não é praça nenhuma. Recusá-la derrubaria o arquivo
    // inteiro por causa de uma linha que ninguém considera dado; aceitá-la
    // cadastraria uma praça a R$ 0,00. Ignorar é a terceira resposta, e é a
    // certa — e ela é CONTADA, para o admin ver que sumiu uma linha.
    if (isPlaceholder(row)) {
      ignored++;
      continue;
    }

    if (!city) {
      errors.push(`Linha ${line}: sem o município.`);
      continue;
    }

    const valuePerHa = parseNumber(valueText);
    if (valuePerHa === null) {
      errors.push(
        `Linha ${line} (${city}): valor ausente ou ilegível na coluna "${price.header}".`,
      );
      continue;
    }
    // O zero é recusado aqui, e não só no DTO: "seguro de graça" não existe, e
    // uma praça a R$ 0,00 entraria na base produzindo permutas com uma linha de
    // seguro que não cobra nada — pior do que a praça ausente, que pelo menos
    // recusa o registro dizendo o que falta.
    if (valuePerHa <= 0) {
      errors.push(`Linha ${line} (${city}): o valor por hectare precisa ser maior que zero.`);
      continue;
    }

    const previous = seen.find((entry) => sameCity(entry.city, city));
    if (previous) {
      errors.push(
        `Linha ${line} (${city}): município repetido, já aparece na linha ${previous.line}.`,
      );
      continue;
    }
    seen.push({ city, line });

    rows.push({ line, city, valuePerHa, note: noteFrom(at, row) });
  }

  if (rows.length === 0 && errors.length === 0) {
    errors.push('A planilha não tem nenhuma linha de município.');
  }

  if (rows.length > MAX_INSURANCE_RATES) {
    errors.push(
      `A planilha tem ${rows.length} municípios, e o limite é ${MAX_INSURANCE_RATES} por carga.`,
    );
  }

  return {
    rows,
    errors,
    priceColumn: { id: price.id, label: price.label, header: price.header },
    ignored,
  };
}

/**
 * A linha é ENFEITE DE PLANILHA: tem texto, e todo número dela é zero.
 *
 * É a "Selecione o Município" da planilha do escritório. A regra olha os
 * NÚMEROS e não o texto de propósito — adivinhar que "Selecione o Município"
 * não é nome de cidade exigiria um palpite sobre o que parece nome de cidade, e
 * ele erraria no dia em que alguém cadastrasse um distrito de nome comprido.
 * Uma praça de verdade tem ao menos um número diferente de zero: se não tem, a
 * linha não diz nada sobre lugar nenhum.
 */
function isPlaceholder(row: string[]): boolean {
  const numbers = row.map(parseNumber).filter((value): value is number => value !== null);
  // DOIS números zerados, e não um: numa planilha de duas colunas (município e
  // valor), a linha com valor zero é indistinguível de um erro de digitação — e
  // ali ela precisa continuar sendo recusada com o número da linha. A linha de
  // seletor só existe em planilha larga, e lá ela zera a coluna inteira: a
  // produção garantida, o preço da saca, o valor segurado, os três prêmios.
  return numbers.length >= 2 && numbers.every((value) => value === 0);
}

/**
 * A OBSERVAÇÃO da praça, montada com o que a planilha traz de contexto.
 *
 * Seguradora, subvenção, cobertura e valor segurado não participam de conta
 * nenhuma — o que a permuta usa é um número por hectare. Mas são exatamente o
 * que o admin precisa ter à mão quando o consultor perguntar por que a praça do
 * cliente dele é mais cara, e perdê-los na carga significaria voltar à planilha
 * original toda vez.
 *
 * Em uma linha só, e não em quatro campos, porque é isso que eles são: nota de
 * rodapé da cotação. O dia em que alguém quiser um relatório POR SEGURADORA, aí
 * sim ela vira coluna — e a carga já sabe onde encontrá-la.
 */
function noteFrom(at: (row: string[], key: ColumnKey) => string, row: string[]): string | null {
  const coverage = asPercent(at(row, 'coverage'));
  const insured = asMoney(at(row, 'insuredValue'));
  const parts = [
    at(row, 'insurer'),
    at(row, 'subsidy'),
    coverage ? `cobertura ${coverage}` : '',
    insured ? `segurado ${insured}/ha` : '',
    at(row, 'note'),
  ].filter((part) => part !== '');

  if (parts.length === 0) return null;
  // O teto do campo (ver `InsuranceRateDto`) cortado aqui, e não na gravação: a
  // observação é conveniência, e não pode ser o motivo de uma carga de 400
  // praças ser recusada.
  const note = parts.join(' • ');
  return note.length <= 300 ? note : `${note.slice(0, 299)}…`;
}

/**
 * O NÍVEL DE COBERTURA como se lê — "65%".
 *
 * A célula chega de dois jeitos, e os dois são a mesma coisa: a planilha real
 * guarda `0,65` com FORMATO de porcentagem (o formato fica na formatação, não
 * no valor, e some na leitura), enquanto a feita à mão escreve "65%" como
 * texto. Acima de 1 já é percentual; de 1 para baixo é fração, e multiplicar é
 * o que devolve o número que a pessoa vê na tela dela.
 *
 * Texto que não é número nenhum sai como veio: a observação é para ser lida, e
 * inventar um formato em cima do que não se entendeu é pior do que repetir.
 */
function asPercent(raw: string): string {
  if (!raw) return '';
  const value = parseNumber(raw);
  if (value === null) return raw;
  const percent = value <= 1 ? value * 100 : value;
  return `${Number(percent.toFixed(2))}%`.replace('.', ',');
}

/** O valor segurado como se lê — "R$ 3.522,20". Ver [asPercent] para o resto. */
function asMoney(raw: string): string {
  if (!raw) return '';
  const value = parseNumber(raw);
  if (value === null) return raw;
  return `R$ ${value.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}
