import ExcelJS from 'exceljs';
import { normalizeName } from './product-name';
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

  /**
   * O que já apareceu, pelas DUAS chaves com que o catálogo casa a linha.
   *
   * Não é zelo: são exatamente as duas chaves do `resolveImported`, que procura
   * o produto primeiro pelo `sku` e, não achando, pelo nome normalizado. Uma
   * linha que colida em qualquer uma delas resolve para o MESMO produto — e
   * duas linhas para um produto só violam o índice `[versionId, productId]`
   * lá na frente, quando já não há número de linha para mostrar a ninguém.
   *
   * O nome é comparado sem acento e sem espaço repetido (ver product-name.ts)
   * porque é assim que o catálogo o compara. Comparar aqui de um jeito e ali
   * de outro era o defeito.
   */
  const seenBySku = new Map<string, number>();
  const seenByName = new Map<string, number>();

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
    const nameKey = normalizeName(name);
    const skuKey = sku?.toLowerCase();

    const previous =
      (skuKey !== undefined ? seenBySku.get(skuKey) : undefined) ?? seenByName.get(nameKey);
    if (previous !== undefined) {
      errors.push(`Linha ${line} (${name}): repetido — já aparece na linha ${previous}.`);
      continue;
    }
    if (skuKey !== undefined) seenBySku.set(skuKey, line);
    seenByName.set(nameKey, line);

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

  // O teto de NEGÓCIO, conferido sobre os produtos de verdade — não sobre
  // linhas de arquivo. É este número que precisa ser o mesmo do `@ArrayMaxSize`
  // do PublishVersionDto: os dois caminhos publicam a mesma tabela, e quem
  // publica por planilha não pode esbarrar num limite que quem publica por JSON
  // não tem.
  if (rows.length > MAX_VERSION_PRICES) {
    errors.push(
      `A tabela tem ${rows.length} produtos — o limite é ${MAX_VERSION_PRICES} por versão.`,
    );
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

/**
 * QUANTOS ITENS DE PREÇO uma versão do Barter aceita — o teto de NEGÓCIO.
 *
 * É a mesma constante que o `PublishVersionDto` usa no `@ArrayMaxSize`, e essa
 * partilha é o ponto: os dois caminhos publicam a MESMA tabela, um por JSON e
 * outro por planilha, e um limite diferente em cada um significa que o arquivo
 * recusa o que o JSON aceita. Já significou — a checagem daqui comparava contra
 * `rowCount`, que inclui cabeçalho e preâmbulo, então uma tabela de exatamente
 * 20.000 preços passava por JSON e era recusada por arquivo.
 *
 * O NÚMERO, porém, precisa ser entregável pelos DOIS, e 20.000 não era por
 * nenhum. Medido:
 *
 * - por JSON, 20.000 itens dão 595 KB e esbarram no limite de 256 KB do corpo
 *   (BODY_LIMIT, em app.setup.ts): 413 antes de a validação sequer rodar. O
 *   teto real daquele caminho ficava perto de 8.600, não em 20.000;
 * - por planilha, 20.000 linhas cabiam no arquivo (0,55 MB contra os 5 MB do
 *   upload) e chegavam até a gravação, onde estouravam o prazo da transação —
 *   P2028 aos 5 s, entregue ao admin como 500 "Erro inesperado no servidor".
 *
 * Ou seja: a constante era compartilhada, e ainda assim cada caminho parava num
 * lugar diferente — o oposto do que ela existe para garantir. A gravação agora
 * é em lote e a transação tem prazo explícito (ver seasons.service.ts), mas o
 * teto continua tendo de caber no mais estreito dos dois caminhos.
 *
 * 5.000 passa com folga pelos dois: 145 KB de JSON contra os 256 KB do corpo. A
 * maior lista de fornecedor que passou por aqui tem 656 itens — sete vezes de
 * folga sobre o uso real, que é o que este teto existe para proteger.
 */
export const MAX_VERSION_PRICES = 5_000;

/**
 * As duas GUARDAS DE MEMÓRIA da planilha já aberta — outra pergunta, outros
 * números.
 *
 * O limite de 5 MB do upload (ver seasons.controller.ts) mede o arquivo
 * COMPRIMIDO, e `.xlsx` é um zip: alguns megabytes de XML repetitivo
 * descomprimem para muito mais. Sem um segundo teto, uma planilha absurda —
 * gerada por engano num export, ou de propósito — viraria uma matriz de
 * milhões de células antes de qualquer regra de negócio ser consultada.
 *
 * `MAX_SHEET_ROWS` sobra sobre o teto de preços de propósito: o cabeçalho não é
 * a primeira linha (ver findHeader — planilha de fornecedor abre com o nome da
 * empresa e a data), e ainda há rodapé. Recusar em `MAX_VERSION_PRICES` exatas
 * reprovaria uma tabela cheia só porque ela tem um título em cima. Quem conta
 * os PREÇOS é o parseSheet, no fim, onde a contagem é a de verdade.
 *
 * `MAX_SHEET_CELLS` limita o PRODUTO linhas × colunas, que é o que consome
 * memória. Uma planilha estreita e comprida e uma larga e curta cabem nos dois
 * limites de dimensão e ainda assim explodem na multiplicação — era essa a
 * fresta que a versão anterior fechava truncando colunas em silêncio, o que
 * trocava um estouro de memória por uma leitura errada sem aviso.
 *
 * O QUE ISTO NÃO FAZ: o `load()` abaixo já descomprimiu o arquivo inteiro
 * quando a contagem acontece — o pico de memória da leitura em si continua
 * limitado apenas pelos 5 MB comprimidos. Fechar isso de vez pede leitura em
 * streaming (`ExcelJS.stream.xlsx.WorkbookReader`), que não funciona a partir
 * de buffer em memória nesta versão da biblioteca. Como a rota exige um
 * usuário com `barter.manage` — ou seja, um admin autenticado —, o caso que
 * sobra é o arquivo grande por engano, e é esse que os tetos pegam.
 */
const MAX_SHEET_ROWS = MAX_VERSION_PRICES + 100;
const MAX_SHEET_CELLS = 1_000_000;

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

  if (sheet.rowCount > MAX_SHEET_ROWS) {
    throw new Error(
      `A planilha tem ${sheet.rowCount} linhas — o limite é ${MAX_SHEET_ROWS}. ` +
        'Confira se o arquivo é a tabela de valores mesmo.',
    );
  }

  // A largura é lida INTEIRA, sem corte. Truncar aqui deslocava silenciosamente
  // a leitura de uma planilha larga: a coluna de preço na posição 70 saía da
  // matriz, e o erro que chegava ao admin falava de cabeçalho ausente num
  // arquivo que tinha o cabeçalho na cara dele. Quem impede o exagero é o teto
  // de células abaixo, que recusa em vez de mutilar.
  const width = sheet.columnCount;
  const cells = sheet.rowCount * width;
  if (cells > MAX_SHEET_CELLS) {
    throw new Error(
      `A planilha tem ${sheet.rowCount} linhas × ${width} colunas — grande demais para ler ` +
        `de uma vez (o limite é ${MAX_SHEET_CELLS.toLocaleString('pt-BR')} células). ` +
        'Confira se o arquivo é a tabela de valores mesmo.',
    );
  }

  const matrix: string[][] = [];
  sheet.eachRow({ includeEmpty: true }, (row) => {
    const cells: string[] = [];
    // `eachCell` pula as vazias; o índice manual mantém as colunas alinhadas —
    // uma célula em branco no meio não pode deslocar o preço para a coluna do
    // custo.
    const count = Math.max(row.cellCount, width);
    for (let column = 1; column <= count; column++) {
      cells.push(cellText(row.getCell(column).value));
    }
    matrix.push(cells);
  });
  return matrix;
}
