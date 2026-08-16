import ExcelJS from 'exceljs';
import { MAX_VERSION_PRICES, parseNumber, parseSheet, readWorkbook } from './version-import';

/**
 * A planilha que chega do fornecedor não é um CSV bem-comportado. Estes testes
 * fixam o que o leitor precisa aguentar sem reclamar — e o que ele precisa
 * RECUSAR, que é a parte que protege o lançamento.
 */
describe('Leitura da planilha do Barter', () => {
  const header = ['codigo', 'nome', 'unidade', 'categoria', 'preco', 'custo'];

  it('lê a tabela e converte número no formato brasileiro', () => {
    const { rows, errors } = parseSheet([
      header,
      ['URE-45', 'Ureia 45%', 'saco 50kg', 'Fertilizantes', 'R$ 1.185,50', '950,00'],
      ['GLI-500', 'Glifosato', 'litro', 'Defensivos', '42.50', '33'],
    ]);

    expect(errors).toEqual([]);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      sku: 'URE-45',
      name: 'Ureia 45%',
      unit: 'saco 50kg',
      productClass: 'Fertilizantes',
      price: 1185.5,
      line: 2,
    });
    expect(rows[1].price).toBe(42.5);
  });

  it('acha o cabeçalho abaixo do título da planilha, em qualquer ordem e com acento', () => {
    const { rows, errors } = parseSheet([
      ['Agro Insumos Ltda — tabela de setembro'],
      [],
      ['Descrição', 'Preço', 'Custo', 'Unidade'],
      ['Semente de soja', '320,00', '250,00', 'saco 40kg'],
    ]);

    expect(errors).toEqual([]);
    expect(rows).toEqual([
      {
        line: 4,
        sku: null,
        name: 'Semente de soja',
        unit: 'saco 40kg',
        productClass: null,
        price: 320,
        requiredPerHa: null,
        unitPending: false,
      },
    ]);
  });

  /**
   * O cabeçalho da lista de preços REAL do fornecedor. `Preço Venda (R$)`
   * derrubava o arquivo inteiro: o "R$" virava um "r" grudado no fim do nome
   * normalizado, a coluna de preço sumia e, sem ela, nem a linha de cabeçalho
   * era reconhecida — 656 produtos voltavam como "não encontrei o cabeçalho".
   */
  it('lê o cabeçalho da lista de preços do fornecedor, com unidade entre parênteses', () => {
    const { rows, errors } = parseSheet([
      [],
      ['Família', 'Código', 'Descrição', 'Preço Venda (R$)'],
      // Como o `readWorkbook` entrega: célula numérica do Excel já virou texto.
      ['HERBICIDAS', '300228', 'HERBIC.2,4-D AGROIMPORT emb.20 l', '5000'],
      ['FERTILIZANTES FOLIARES', '305115', 'VALENCE V 12 NI emb.10KG', '57.2761'],
    ]);

    expect(errors).toEqual([]);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      sku: '300228',
      name: 'HERBIC.2,4-D AGROIMPORT emb.20 l',
      productClass: 'HERBICIDAS',
      price: 5000,
      // Sem coluna de unidade: a embalagem sai da própria descrição.
      unit: '20 L',
    });
    expect(rows[1].price).toBe(57.2761);
  });

  it('sem cabeçalho reconhecível, recusa o arquivo em vez de adivinhar', () => {
    const { rows, errors } = parseSheet([
      ['Ureia', '185'],
      ['Glifosato', '42'],
    ]);
    expect(rows).toEqual([]);
    expect(errors[0]).toContain('cabeçalho');
  });

  it('aponta o problema COM O NÚMERO DA LINHA — é assim que se corrige planilha', () => {
    const { errors } = parseSheet([
      header,
      ['A', 'Sem preço', 'litro', '', '', '10'],
      ['B', 'Preço zerado', 'litro', '', '0', '0'],
      ['', '', '', '', '', ''],
      ['D', 'Ureia', 'saco', '', '185', '150'],
      ['D', 'Ureia de novo', 'saco', '', '190', '150'],
    ]);

    expect(errors).toEqual([
      'Linha 2 (Sem preço): preço ausente ou ilegível.',
      'Linha 3 (Preço zerado): o preço precisa ser maior que zero.',
      'Linha 6 (Ureia de novo): repetido — já aparece na linha 5.',
    ]);
  });

  /**
   * A REGRESSÃO: a linha repetida precisa ser pega pelas mesmas chaves com que
   * o catálogo casa o produto (sku, e nome normalizado sem acento).
   *
   * Comparando `nome.toLowerCase()`, como era antes, `Ureia 45%` e `Uréia  45%`
   * passavam daqui como dois produtos e chegavam no `resolveImported` como um
   * só — duas linhas de preço para o mesmo produto, o que estoura o índice
   * único `[versionId, productId]`. O que o admin via era "Já existe um
   * registro com estes dados.", sem linha nenhuma, sobre um arquivo que este
   * leitor tinha acabado de aprovar. E os produtos já criados ficavam para trás.
   */
  it('recusa nomes que só diferem por ACENTO — o catálogo os trata como um', () => {
    const { errors } = parseSheet([
      header,
      ['', 'Ureia 45%', 'saco', '', '185', ''],
      ['', 'Uréia 45%', 'saco', '', '190', ''],
    ]);
    expect(errors).toEqual(['Linha 3 (Uréia 45%): repetido — já aparece na linha 2.']);
  });

  it('recusa nomes que só diferem por ESPAÇO repetido', () => {
    const { errors } = parseSheet([
      header,
      ['', 'Ureia 45%', 'saco', '', '185', ''],
      ['', 'Ureia  45%', 'saco', '', '190', ''],
    ]);
    expect(errors).toEqual(['Linha 3 (Ureia  45%): repetido — já aparece na linha 2.']);
  });

  /**
   * SKUs diferentes não salvam nomes iguais. O casamento tenta o sku primeiro,
   * mas cai no nome quando ele não bate com nada no cadastro — e aí as duas
   * linhas resolvem para o mesmo produto do mesmo jeito.
   */
  it('recusa o mesmo nome sob códigos de fornecedor diferentes', () => {
    const { errors } = parseSheet([
      header,
      ['URE-1', 'Ureia 45%', 'saco', '', '185', ''],
      ['URE-2', 'Ureia 45%', 'saco', '', '190', ''],
    ]);
    expect(errors).toEqual(['Linha 3 (Ureia 45%): repetido — já aparece na linha 2.']);
  });

  it('nomes de verdade diferentes continuam passando', () => {
    const { rows, errors } = parseSheet([
      header,
      ['A', 'Ureia 45%', 'saco', '', '185', ''],
      ['B', 'Ureia 46%', 'saco', '', '190', ''],
    ]);
    expect(errors).toEqual([]);
    expect(rows).toHaveLength(2);
  });

  it('ignora linha em branco e o rodapé de observações', () => {
    const { rows, errors } = parseSheet([
      header,
      ['URE', 'Ureia', 'saco', '', '185', '150'],
      [],
      ['Tabela válida enquanto durar o estoque'],
    ]);
    expect(errors).toEqual([]);
    expect(rows).toHaveLength(1);
  });

  /**
   * A lista real não tem coluna de unidade: a embalagem vem no fim da
   * descrição. Ver unit-from-name.ts.
   */
  it('sem coluna de unidade, a embalagem sai da descrição — e da classe', () => {
    const { rows } = parseSheet([
      ['classe', 'nome', 'preco'],
      ['HERBICIDAS', 'HERBIC.AMINOL 806 emb.20 l', '19,90'],
      ['FERTILIZANTES', 'ADUBO 10-20-10 CIBRA BIG-BAG', '3500'],
      // Nome não diz nada; a CLASSE diz: fertilizante a peso é tonelada.
      ['FERTILIZANTES', 'UREIA PLUS (45-00-00)', '2800'],
      // Nem o nome nem a classe resolvem: entra marcado para revisão.
      ['INOCULANTES', 'INOCULANTE GENÉRICO', '90'],
    ]);
    expect(rows.map((r) => r.unit)).toEqual(['20 L', 'big-bag', 'tonelada', 'unidade']);
    expect(rows.map((r) => r.unitPending)).toEqual([false, false, false, true]);
  });

  describe('parseNumber', () => {
    it.each([
      ['1.234,56', 1234.56],
      ['1234,56', 1234.56],
      ['1234.56', 1234.56],
      ['R$ 185,00', 185],
      ['  42 ', 42],
      ['', null],
      ['—', null],
    ])('%s → %s', (raw, expected) => {
      expect(parseNumber(raw)).toBe(expected);
    });
  });

  it('lê um .xlsx de verdade, respeitando colunas vazias no meio', async () => {
    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Tabela');
    sheet.addRow(['codigo', 'nome', 'unidade', 'classe', 'preco']);
    // A coluna "classe" vem vazia: se o leitor pulasse a célula em branco, o
    // preço escorregaria para a coluna anterior.
    sheet.addRow(['URE-45', 'Ureia 45%', 'saco 50kg', null, 185.5]);
    const buffer = (await workbook.xlsx.writeBuffer()) as unknown as Buffer;

    const { rows, errors } = parseSheet(await readWorkbook(Buffer.from(buffer)));
    expect(errors).toEqual([]);
    expect(rows[0]).toMatchObject({
      name: 'Ureia 45%',
      price: 185.5,
      productClass: null,
    });
  });

  it('arquivo que não é planilha vira erro legível, não um stack trace', async () => {
    await expect(readWorkbook(Buffer.from('isto não é um xlsx'))).rejects.toThrow(/\.xlsx/);
  });

  /**
   * OS DOIS TETOS, que respondem perguntas diferentes.
   *
   * O de NEGÓCIO conta produtos e é o mesmo do `PublishVersionDto` — publicar
   * por planilha não pode esbarrar num limite que publicar por JSON não tem.
   * O de MEMÓRIA conta linhas e células do arquivo cru: o limite de 5 MB do
   * upload mede o `.xlsx` COMPRIMIDO, e ele é um zip — 20 mil linhas cabem em
   * menos de 300 KB.
   */
  describe('tetos', () => {
    /** Uma matriz de produtos, direto — sem pagar a geração de um zip. */
    const tableWith = (products: number): string[][] => [
      ['nome', 'preco'],
      ...Array.from({ length: products }, (_, i) => [`Item ${i}`, '10,00']),
    ];

    /**
     * A REGRESSÃO que motivou a separação dos dois tetos. Antes, o teto de
     * linhas era comparado contra `rowCount` — que inclui o cabeçalho —, então
     * uma tabela de exatamente 20.000 produtos tinha 20.001 linhas e era
     * recusada. Por JSON, a mesma tabela passava.
     */
    it('uma tabela com o máximo exato de produtos é aceita', () => {
      const { rows, errors } = parseSheet(tableWith(MAX_VERSION_PRICES));
      expect(errors).toEqual([]);
      expect(rows).toHaveLength(MAX_VERSION_PRICES);
    });

    // Os números saem da CONSTANTE, não escritos à mão: fixá-los aqui fazia
    // estes dois testes reprovarem por o teto ter mudado — que é uma decisão,
    // não um defeito —, escondendo o que eles de fato guardam (que a contagem é
    // de produtos e a mensagem diz quantos vieram).
    it('um produto além do máximo é recusado, dizendo quantos vieram', () => {
      const { errors } = parseSheet(tableWith(MAX_VERSION_PRICES + 1));
      expect(errors.join(' ')).toContain(
        `A tabela tem ${MAX_VERSION_PRICES + 1} produtos — o limite é ${MAX_VERSION_PRICES}`,
      );
    });

    it('arquivo com linhas demais é recusado antes de virar matriz', async () => {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Tabela');
      sheet.addRow(['nome', 'preco']);
      for (let linha = 0; linha < MAX_VERSION_PRICES + 200; linha++) {
        sheet.addRow([`Item ${linha}`, '10,00']);
      }
      const buffer = Buffer.from((await workbook.xlsx.writeBuffer()) as unknown as Buffer);

      await expect(readWorkbook(buffer)).rejects.toThrow(
        new RegExp(`linhas — o limite é ${MAX_VERSION_PRICES + 100}`),
      );
    });

    /**
     * A planilha LARGA. Antes as colunas eram truncadas em 64 sem aviso: a
     * coluna de preço na posição 70 sumia da matriz, e o admin recebia "não
     * encontrei o cabeçalho" sobre um arquivo que tinha o cabeçalho. Agora a
     * largura é lida inteira, e quem contém o exagero é o teto de células.
     */
    it('planilha larga é lida inteira, sem truncar a coluna de preço', async () => {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Tabela');
      const padding = Array.from({ length: 70 }, (_, i) => `col${i}`);
      sheet.addRow([...padding, 'nome', 'preco']);
      sheet.addRow([...padding.map(() => ''), 'Ureia 45%', '185,50']);
      const buffer = Buffer.from((await workbook.xlsx.writeBuffer()) as unknown as Buffer);

      const { rows, errors } = parseSheet(await readWorkbook(buffer));
      expect(errors).toEqual([]);
      expect(rows[0]).toMatchObject({ name: 'Ureia 45%', price: 185.5 });
    });
  });
});
