import ExcelJS from 'exceljs';
import { parseNumber, parseSheet, readWorkbook } from './version-import';

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
      cost: 950,
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
        cost: 250,
        requiredPerHa: null,
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
      // A lista do fornecedor não traz unidade nem custo: a embalagem vem na
      // descrição, e o custo não é dado que ele compartilha.
      unit: 'unidade',
      cost: 0,
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
      ['C', 'Custo acima do preço', 'litro', '', '10', '90'],
      ['', '', '', '', '', ''],
      ['D', 'Ureia', 'saco', '', '185', '150'],
      ['D', 'Ureia de novo', 'saco', '', '190', '150'],
    ]);

    expect(errors).toEqual([
      'Linha 2 (Sem preço): preço ausente ou ilegível.',
      'Linha 3 (Preço zerado): o preço precisa ser maior que zero.',
      'Linha 4 (Custo acima do preço): o custo está acima do preço de venda.',
      'Linha 7 (Ureia de novo): repetido — já aparece na linha 6.',
    ]);
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

  it('custo é opcional — sem ele a linha vale, com lucro zero', () => {
    const { rows, errors } = parseSheet([header, ['X', 'Adjuvante', 'litro', '', '30', '']]);
    expect(errors).toEqual([]);
    expect(rows[0].cost).toBe(0);
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
    sheet.addRow(['codigo', 'nome', 'unidade', 'categoria', 'preco', 'custo']);
    // A coluna "categoria" vem vazia: se o leitor pulasse a célula em branco, o
    // preço escorregaria para a coluna do custo.
    sheet.addRow(['URE-45', 'Ureia 45%', 'saco 50kg', null, 185.5, 150]);
    const buffer = (await workbook.xlsx.writeBuffer()) as unknown as Buffer;

    const { rows, errors } = parseSheet(await readWorkbook(Buffer.from(buffer)));
    expect(errors).toEqual([]);
    expect(rows[0]).toMatchObject({
      name: 'Ureia 45%',
      price: 185.5,
      cost: 150,
      productClass: null,
    });
  });

  it('arquivo que não é planilha vira erro legível, não um stack trace', async () => {
    await expect(readWorkbook(Buffer.from('isto não é um xlsx'))).rejects.toThrow(/\.xlsx/);
  });
});
