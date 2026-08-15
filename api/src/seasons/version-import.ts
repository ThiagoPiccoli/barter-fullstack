import ExcelJS from 'exceljs';
import { unitFor } from './unit-from-name';

/**
 * A PLANILHA que lança um Barter.
 *
 * O admin recebe a tabela do fornecedor em Excel e é isso que ele sobe — não
 * uma tela de digitação item a item. Este arquivo transforma aquela planilha em
 * linhas conferidas, e é escrito para aguentar planilha de gente: cabeçalho em
 * qualquer ordem, com ou sem acento, número com vírgula, "R$" no meio do valor,
 * linhas em branco e uma nota de rodapé no fim.
 *
 * O que ela NÃO traz é custo: a lista do fornecedor tem preço de venda e mais
 * nada. Por isso o Barter mede vendas, não lucro.
 *
 * A separação em duas etapas é de propósito:
 *
 *   readWorkbook(buffer) → string[][]     (a única parte que conhece xlsx)
 *   parseSheet(string[][]) → ImportResult (a regra, testável sem arquivo)
 *
 * Erro de leitura é reportado POR LINHA e o service recusa o arquivo inteiro se
 * houver qualquer um. Meia-tabela publicada seria pior do que nenhuma: o que
 * ficou de fora não é permutável, e ninguém perceberia até o consultor
 * esbarrar no insumo que faltou.
 */

/** Uma linha válida da planilha, ainda não casada com o catálogo. */
export interface ImportRow {
  /** Número da linha na planilha — é o que o admin procura para corrigir. */
  line: number;
  sku: string | null;
  name: string;
  unit: string;
  /** Nome (ou slug) da CLASSE do insumo, como veio na planilha. */
  productClass: string | null;

  /**
   * A unidade NÃO pôde ser determinada: nem a planilha traz coluna, nem o nome
   * diz a embalagem, nem a classe tem padrão. O item entra com "unidade" e
   * marcado para o admin escrever depois — ver Product.unitPending.
   */
  unitPending: boolean;
  price: number;
  /** Exigência por hectare, quando a planilha traz a coluna. */
  requiredPerHa: number | null;
}

export interface ImportResult {
  rows: ImportRow[];
  errors: string[];
}

/** Colunas que o leitor entende, cada uma com os nomes que já vimos no campo. */
const COLUMNS = {
  sku: ['codigo', 'cod', 'sku', 'referencia', 'ref', 'codigoproduto'],
  name: ['nome', 'produto', 'descricao', 'insumo', 'item', 'nomeproduto'],
  unit: ['unidade', 'un', 'und', 'unid', 'medida', 'embalagem'],
  productClass: ['classe', 'categoria', 'pasta', 'grupo', 'familia', 'linha'],
  price: ['preco', 'valor', 'precovenda', 'valorvenda', 'venda', 'precounitario'],
  requiredPerHa: ['exigenciaha', 'exigencia', 'minimoha', 'minimoporha', 'dose', 'doseha'],
} as const;

type ColumnKey = keyof typeof COLUMNS;

/**
 * Texto de cabeçalho reduzido à forma comparável: sem acento, espaço ou caixa.
 *
 * O que está entre PARÊNTESES cai fora antes da comparação, e isso não é
 * detalhe: a planilha real traz `Preço Venda (R$)`, e o "R$" deixava um "r"
 * grudado no fim (`precovendar`). Nenhum apelido batia, a coluna de preço
 * sumia — e sem ela o leitor não reconhece a linha de cabeçalho, então o
 * arquivo inteiro voltava com "não encontrei o cabeçalho". Unidade entre
 * parênteses é como se escreve cabeçalho de planilha: descreve a coluna, não a
 * nomeia.
 */
function normalizeHeader(value: string): string {
  return value
    .replace(/\([^)]*\)/g, '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

/**
 * Número como o Brasil escreve. Aceita "1.234,56", "1234,56", "1234.56",
 * "R$ 185,00" e o que vier de célula numérica do Excel.
 *
 * Quando só há ponto, ele é tratado como decimal ("185.00" → 185). Célula
 * numérica de verdade nem passa por aqui — chega como número —, então o caso
 * ambíguo ("1.234" querendo dizer mil e duzentos) só apareceria se alguém
 * formatasse a coluna como texto.
 */
export function parseNumber(raw: string): number | null {
  const cleaned = raw.replace(/[^\d,.-]/g, '').trim();
  if (!cleaned) return null;

  const hasComma = cleaned.includes(',');
  const normalized = hasComma ? cleaned.replace(/\./g, '').replace(',', '.') : cleaned;

  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
}

/** Onde cada coluna caiu, a partir da linha de cabeçalho. */
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
 * Acha a linha de cabeçalho. Não assumimos que seja a primeira: planilha de
 * fornecedor costuma abrir com o nome da empresa e a data da tabela.
 */
function findHeader(matrix: string[][]): number {
  for (let index = 0; index < Math.min(matrix.length, 20); index++) {
    const columns = mapColumns(matrix[index]);
    if (columns.name !== undefined && columns.price !== undefined) return index;
  }
  return -1;
}

/** A planilha (já como matriz de texto) virando linhas conferidas. */
export function parseSheet(matrix: string[][]): ImportResult {
  const headerIndex = findHeader(matrix);
  if (headerIndex === -1) {
    return {
      rows: [],
      errors: [
        'Não encontrei o cabeçalho da tabela. A planilha precisa de uma linha com as colunas "nome" e "preço".',
      ],
    };
  }

  const columns = mapColumns(matrix[headerIndex]);
  const rows: ImportRow[] = [];
  const errors: string[] = [];
  const seen = new Map<string, number>();

  const at = (row: string[], key: ColumnKey): string => {
    const index = columns[key];
    return index === undefined ? '' : (row[index] ?? '').trim();
  };

  for (let index = headerIndex + 1; index < matrix.length; index++) {
    const row = matrix[index];
    const line = index + 1;
    if (row.every((cell) => !cell || !cell.trim())) continue;

    const name = at(row, 'name');
    const priceText = at(row, 'price');
    // Rodapé ("Tabela válida até…") entra como linha só com texto na primeira
    // coluna: sem preço e sem nome, não é produto — é ruído, e ruído se ignora.
    if (!name && !priceText) continue;

    if (!name) {
      errors.push(`Linha ${line}: sem o nome do produto.`);
      continue;
    }

    const price = parseNumber(priceText);
    if (price === null) {
      errors.push(`Linha ${line} (${name}): preço ausente ou ilegível.`);
      continue;
    }
    if (price <= 0) {
      errors.push(`Linha ${line} (${name}): o preço precisa ser maior que zero.`);
      continue;
    }

    const sku = at(row, 'sku') || null;
    const key = (sku ?? name).toLowerCase();
    const previous = seen.get(key);
    if (previous !== undefined) {
      errors.push(`Linha ${line} (${name}): repetido — já aparece na linha ${previous}.`);
      continue;
    }
    seen.set(key, line);

    const requiredText = at(row, 'requiredPerHa');
    const requiredPerHa = requiredText ? parseNumber(requiredText) : null;

    rows.push({
      line,
      sku,
      name,
      ...unitOf(at(row, 'unit'), name, at(row, 'productClass') || null),
      productClass: at(row, 'productClass') || null,
      price,
      requiredPerHa: requiredPerHa !== null && requiredPerHa > 0 ? requiredPerHa : null,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    errors.push('A planilha não tem nenhuma linha de produto.');
  }
  return { rows, errors };
}

/**
 * A unidade do item e o sinal de que ela é confiável.
 *
 * Ordem: coluna da planilha → embalagem escondida no nome (`emb.20 l`,
 * `BIG-BAG`) → padrão da classe (fertilizante a peso é tonelada). Falhando
 * tudo, o item entra com "unidade" e MARCADO: é melhor uma dúzia de itens
 * pedindo revisão do que 656 com uma unidade inventada.
 */
function unitOf(
  fromSheet: string,
  name: string,
  productClass: string | null,
): { unit: string; unitPending: boolean } {
  if (fromSheet) return { unit: fromSheet, unitPending: false };
  const read = unitFor({ name, productClass });
  return read ? { unit: read, unitPending: false } : { unit: 'unidade', unitPending: true };
}

/** O texto de uma célula, seja ela número, fórmula, data ou texto rico. */
function cellText(value: ExcelJS.CellValue): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') {
    const cell = value as {
      result?: ExcelJS.CellValue;
      richText?: { text: string }[];
      text?: string;
    };
    if (cell.result !== undefined) return cellText(cell.result);
    if (cell.richText) return cell.richText.map((part) => part.text).join('');
    if (cell.text !== undefined) return cell.text;
  }
  return '';
}

/** Lê a primeira aba do arquivo como uma matriz de texto. */
export async function readWorkbook(buffer: Buffer): Promise<string[][]> {
  const workbook = new ExcelJS.Workbook();
  try {
    await workbook.xlsx.load(buffer as unknown as ArrayBuffer);
  } catch {
    throw new Error('Não consegui ler o arquivo. Envie uma planilha .xlsx válida.');
  }

  const sheet = workbook.worksheets[0];
  if (!sheet) throw new Error('A planilha está vazia.');

  const matrix: string[][] = [];
  sheet.eachRow({ includeEmpty: true }, (row) => {
    const cells: string[] = [];
    // `eachCell` pula as vazias; o índice manual mantém as colunas alinhadas —
    // uma célula em branco no meio não pode deslocar o preço para a coluna do
    // custo.
    const count = Math.max(row.cellCount, sheet.columnCount);
    for (let column = 1; column <= count; column++) {
      cells.push(cellText(row.getCell(column).value));
    }
    matrix.push(cells);
  });
  return matrix;
}
