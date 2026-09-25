import { MAX_INSURANCE_RATES, parseInsuranceSheet } from './insurance-import';

/**
 * A PLANILHA REAL da seguradora, com os títulos como eles vêm. Ela é a
 * especificação deste leitor: o resto dos casos abaixo é a planilha simples
 * feita à mão pelo escritório, que tem uma coluna de valor só.
 */
const SEGURADORA = [
  'Município',
  'Produção Garantida (sc/ha)',
  'Preço Estipulado (R$/sc)',
  'Valor Segurado (R$/ha)',
  'Nível de Cobertura (%)',
  'SEM Subvenção (R$/ha)',
  'COM Subvenção (R$/ha)',
  'Reajuste para Safra (maio/26) + 1,5% financeiro',
  'Valor em SC de Soja/ha',
  'Seguradora',
  'Subvenção',
];

/** A linha de seletor da planilha do escritório: texto, e todo número zerado. */
const SELETOR = [
  'Selecione o Município',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
  '0,00',
];

const TUPANCIRETA = [
  'TUPANCIRETÃ',
  '32,02Sc',
  'R$ 110,00',
  'R$ 3.522,20',
  '65%',
  '369,83',
  '369,83',
  '416,61',
  '3,14',
  'BTG',
  'Sem Subvenção',
];

/** A praça SUBVENCIONADA — a que separa as três colunas de valor. */
const CAPAO_DO_CIPO = [
  'CAPÃO DO CIPO',
  '25,40Sc',
  'R$ 110,00',
  'R$ 2.794,46',
  '65%',
  '246,75',
  '197,40',
  '222,37',
  '1,67',
  'SANCOR',
  'Com Subvenção',
];

/**
 * A planilha da seguradora, como ela chega: cabeçalho abaixo do título, valor
 * com "R$", a UF colada ou separada por espaço, e um rodapé de validade no fim.
 * Estes testes fixam o que o leitor aguenta — e o que ele RECUSA, que é a parte
 * que protege a base.
 */
describe('A planilha da seguradora', () => {
  it('é lida inteira, pela coluna do reajuste', () => {
    const { rows, errors, priceColumn } = parseInsuranceSheet([
      SEGURADORA,
      SELETOR,
      TUPANCIRETA,
      CAPAO_DO_CIPO,
    ]);

    expect(errors).toEqual([]);
    // A COLUNA ESCOLHIDA volta escrita como estava no arquivo: é assim que o
    // admin percebe, no mesmo minuto, que a planilha deste ano veio com os
    // títulos trocados.
    expect(priceColumn).toEqual({
      id: 'reajuste',
      label: 'reajuste para a safra',
      header: 'Reajuste para Safra (maio/26) + 1,5% financeiro',
    });

    expect(rows.map((row) => [row.city, row.valuePerHa])).toEqual([
      ['TUPANCIRETÃ', 416.61],
      ['CAPÃO DO CIPO', 222.37],
    ]);
  });

  /**
   * O PONTO DA ESCOLHA: na praça subvencionada, as três colunas são três
   * preços. Cobrar a "SEM Subvenção" de quem tem subvenção seria cobrar do
   * produtor um dinheiro que o governo pagou.
   */
  it('as três colunas de valor dão três preços, e a escolha pode ser forçada', () => {
    const planilha = [SEGURADORA, CAPAO_DO_CIPO];

    expect(parseInsuranceSheet(planilha).rows[0].valuePerHa).toBe(222.37);
    expect(parseInsuranceSheet(planilha, 'comSubvencao').rows[0].valuePerHa).toBe(197.4);
    expect(parseInsuranceSheet(planilha, 'semSubvencao').rows[0].valuePerHa).toBe(246.75);
  });

  /**
   * A coluna escolhida que NÃO está no arquivo recusa a carga, em vez de cair
   * para a seguinte: trocar a escolha de quem pediu produziria uma base inteira
   * cobrando outro número, em silêncio.
   */
  it('a coluna escolhida que não existe recusa o arquivo', () => {
    const { rows, errors } = parseInsuranceSheet(
      [
        ['municipio', 'valor por hectare (R$)'],
        ['Maringá/PR', '85,00'],
      ],
      'reajuste',
    );

    expect(rows).toEqual([]);
    expect(errors[0]).toContain('reajuste para a safra');
  });

  /** O contexto da cotação sobrevive à carga, como observação da praça. */
  it('seguradora, subvenção, cobertura e valor segurado viram a observação', () => {
    const { rows } = parseInsuranceSheet([SEGURADORA, CAPAO_DO_CIPO]);

    expect(rows[0].note).toBe('SANCOR • Com Subvenção • cobertura 65% • segurado R$ 2.794,46/ha');
  });

  /**
   * A CÉLULA DE PORCENTAGEM chega como fração: a planilha real guarda `0,65` e
   * mostra "65%" — o formato fica na formatação, e ela some na leitura. Sem
   * traduzir, a observação diria "cobertura 0.65" para quem abrisse a praça.
   */
  it('lê a cobertura em fração e o valor segurado em número cru', () => {
    const { rows } = parseInsuranceSheet([
      SEGURADORA,
      [
        'SANTIAGO',
        '27,72',
        '110',
        '3049.2',
        '0.7',
        '351,27',
        '351,27',
        '395,70',
        '2,98',
        'BTG',
        'Sem Subvenção',
      ],
    ]);

    expect(rows[0].note).toBe('BTG • Sem Subvenção • cobertura 70% • segurado R$ 3.049,20/ha');
  });

  /**
   * A LINHA DE SELETOR é ignorada e CONTADA — e é a contagem que a distingue de
   * um erro engolido: o admin vê que sumiu uma linha do arquivo.
   */
  it('a linha "Selecione o Município" é ignorada, e contada', () => {
    const { rows, errors, ignored } = parseInsuranceSheet([SEGURADORA, SELETOR, TUPANCIRETA]);

    expect(errors).toEqual([]);
    expect(ignored).toBe(1);
    expect(rows).toHaveLength(1);
  });

  /**
   * A coluna "Valor Segurado" é a IMPORTÂNCIA SEGURADA (R$ 3.522,20/ha), e não
   * o prêmio. Confundi-la com o preço cobraria do produtor oito vezes o seguro
   * — é o erro mais caro que este leitor pode cometer, e o que o mantém longe
   * dele é ela não estar entre as colunas de preço.
   */
  it('nunca confunde o valor segurado com o prêmio', () => {
    const { rows } = parseInsuranceSheet([SEGURADORA, TUPANCIRETA]);
    expect(rows[0].valuePerHa).not.toBe(3522.2);
  });

  /**
   * O MESMO MUNICÍPIO escrito de dois jeitos é uma linha só — as duas na base
   * fariam a permuta encontrar duas taxas para o mesmo produtor.
   */
  it('recusa a praça repetida com e sem UF', () => {
    const { rows, errors } = parseInsuranceSheet([
      SEGURADORA,
      TUPANCIRETA,
      [...TUPANCIRETA.slice(0, 0), 'Tupanciretã/RS', ...TUPANCIRETA.slice(1)],
    ]);

    expect(rows).toHaveLength(1);
    expect(errors[0]).toContain('repetido');
  });
});

describe('Leitura da planilha de seguros por município', () => {
  const header = ['municipio', 'valor por hectare (R$)', 'observacao'];

  it('lê a base e converte número no formato brasileiro', () => {
    const { rows, errors } = parseInsuranceSheet([
      header,
      ['Maringá/PR', 'R$ 85,00', 'Soja 25/26'],
      ['Sorriso/MT', '1.140,50', ''],
    ]);

    expect(errors).toEqual([]);
    expect(rows).toEqual([
      { line: 2, city: 'Maringá/PR', valuePerHa: 85, note: 'Soja 25/26' },
      { line: 3, city: 'Sorriso/MT', valuePerHa: 1140.5, note: null },
    ]);
  });

  it('acha o cabeçalho abaixo do título, em qualquer ordem e com acento', () => {
    const { rows, errors } = parseInsuranceSheet([
      ['Seguradora Campo Ltda — cotação de setembro'],
      [],
      ['Prêmio (R$/ha)', 'Cidade'],
      ['92,50', 'Campo Mourão/PR'],
    ]);

    expect(errors).toEqual([]);
    expect(rows).toEqual([{ line: 4, city: 'Campo Mourão/PR', valuePerHa: 92.5, note: null }]);
  });

  it('ignora linha em branco e rodapé que não cai na coluna do município', () => {
    const { rows, errors } = parseInsuranceSheet([
      header,
      ['Maringá/PR', '85,00', ''],
      [],
      ['', '', 'Cotação válida até 30/11/2026'],
    ]);

    expect(errors).toEqual([]);
    expect(rows).toHaveLength(1);
  });

  /**
   * O rodapé escrito DEBAIXO da coluna do município vira erro, e não linha
   * ignorada — a mesma resposta do leitor da tabela de valores.
   *
   * É deliberado: adivinhar que "Cotação válida até…" não é uma praça exigiria
   * um palpite sobre o que parece nome de cidade, e o palpite erraria no dia em
   * que alguém cadastrasse um distrito de nome comprido. O erro nomeia a linha,
   * e apagá-la custa um segundo; aceitar em silêncio uma linha que o leitor não
   * entendeu é o que não se pode fazer com uma base que precifica permuta.
   */
  it('recusa o rodapé escrito na coluna do município, nomeando a linha', () => {
    const { errors } = parseInsuranceSheet([
      header,
      ['Maringá/PR', '85,00', ''],
      ['Cotação válida até 30/11/2026'],
    ]);

    expect(errors).toEqual([
      'Linha 3 (Cotação válida até 30/11/2026): valor ausente ou ilegível na coluna ' +
        '"valor por hectare (R$)".',
    ]);
  });

  /**
   * A repetição é conferida pela MESMA chave com que a permuta procura a praça
   * — sem acento, sem caixa, sem espaço em volta da barra. Comparar o texto cru
   * deixaria as duas passarem, e a violação do índice único apareceria lá na
   * gravação, sem número de linha para mostrar ao admin.
   */
  it('recusa o mesmo município escrito de dois jeitos', () => {
    const { rows, errors } = parseInsuranceSheet([
      header,
      ['Maringá/PR', '85,00', ''],
      ['maringa / pr', '91,00', ''],
    ]);

    expect(rows).toHaveLength(1);
    expect(errors).toEqual(['Linha 3 (maringa / pr): município repetido, já aparece na linha 2.']);
  });

  it('recusa linha sem município e linha sem valor legível', () => {
    const { errors } = parseInsuranceSheet([
      header,
      ['', '85,00', ''],
      ['Sorriso/MT', 'a combinar', ''],
    ]);

    expect(errors).toEqual([
      'Linha 2: sem o município.',
      'Linha 3 (Sorriso/MT): valor ausente ou ilegível na coluna "valor por hectare (R$)".',
    ]);
  });

  /**
   * Zero não é seguro de graça: é linha pela metade. Aceita, ela produziria
   * permutas com uma linha de seguro que não cobra nada — pior do que a praça
   * ausente, que ao menos recusa o registro dizendo o que falta.
   */
  it('recusa valor zerado ou negativo', () => {
    const { rows, errors } = parseInsuranceSheet([
      header,
      ['Maringá/PR', '0', ''],
      ['Sorriso/MT', '-140', ''],
    ]);

    expect(rows).toEqual([]);
    // Uma por linha, e nada além: "a planilha não tem nenhuma linha" só entra
    // quando o arquivo passou limpo e mesmo assim não produziu nada — dizê-lo
    // aqui repetiria, em outras palavras, o que os dois erros já explicaram.
    expect(errors).toHaveLength(2);
    expect(errors[0]).toContain('maior que zero');
  });

  it('sem cabeçalho reconhecível, recusa o arquivo dizendo o que falta', () => {
    const { rows, errors } = parseInsuranceSheet([
      ['Relatório de sinistros'],
      ['Maringá/PR', '85,00'],
    ]);

    expect(rows).toEqual([]);
    expect(errors[0]).toContain('"município"');
    expect(errors[0]).toContain('valor por hectare');
  });

  it('a planilha vazia não passa como base vazia', () => {
    const { errors } = parseInsuranceSheet([header]);
    expect(errors).toEqual(['A planilha não tem nenhuma linha de município.']);
  });

  it('recusa a carga acima do teto de praças', () => {
    const rows = Array.from({ length: MAX_INSURANCE_RATES + 1 }, (_, index) => [
      `Município ${index}/PR`,
      '85,00',
      '',
    ]);
    const { errors } = parseInsuranceSheet([header, ...rows]);

    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain(String(MAX_INSURANCE_RATES));
  });
});
