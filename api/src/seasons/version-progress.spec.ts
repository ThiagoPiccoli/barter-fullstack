import {
  anyGoalMet,
  closingReasonOf,
  countsAsRealized,
  goalsOf,
  isOpenAt,
  realizedFrom,
} from './version-progress';

const item = (kind: string, quantity: number, unitValue: number) => ({
  kind,
  quantity,
  unitValue,
});

/**
 * A LINHA DE PAGAMENTO, com a cultura junto — é o `productId` dela que diz de
 * qual grão são as sacas da permuta (ver `BarterItem` no schema).
 */
const grainItem = (
  productId: number,
  productName: string,
  quantity: number,
  unitValue: number,
) => ({ kind: 'grain', quantity, unitValue, productId, productName });

const SOJA = { grainId: 1, grainName: 'Soja' };
const MILHO = { grainId: 2, grainName: 'Milho' };

describe('Metas e vigência da versão do Barter', () => {
  const barters = [
    {
      status: 'approved',
      items: [grainItem(1, 'Soja', 100, 148.5), item('input', 10, 115), item('input', 20, 18.9)],
    },
    { status: 'approved', items: [grainItem(1, 'Soja', 50, 148.5), item('input', 5, 320)] },
    // Não entram na conta: uma ainda pode ser negada, a outra já foi.
    { status: 'pending', items: [grainItem(1, 'Soja', 999, 148.5), item('input', 99, 115)] },
    { status: 'denied', items: [grainItem(1, 'Soja', 999, 148.5), item('input', 99, 115)] },
  ];

  it('o realizado conta só as permutas aprovadas', () => {
    expect(realizedFrom(barters)).toEqual({
      sales: 10 * 115 + 20 * 18.9 + 5 * 320, // 3128
      sacks: [{ grainId: 1, grainName: 'Soja', sacks: 150 }],
      barters: 2,
    });
  });

  /**
   * AS SACAS SÃO POR CULTURA, e esta é a razão de elas terem deixado de ser um
   * número só: 150 de soja e 80 de milho não são 230 de coisa nenhuma — são dois
   * compromissos de entrega, com compradores e calendários diferentes.
   */
  it('as sacas são separadas por cultura', () => {
    const comMilho = [
      ...barters,
      { status: 'approved', items: [grainItem(2, 'Milho', 80, 64.5), item('input', 1, 100)] },
    ];
    expect(realizedFrom(comMilho).sacks).toEqual([
      { grainId: 2, grainName: 'Milho', sacks: 80 },
      { grainId: 1, grainName: 'Soja', sacks: 150 },
    ]);
  });

  /**
   * FATURADA CONTINUA REALIZADA. É a mesma permuta aprovada, um posto adiante —
   * e sem isto ela sumiria da meta no dia em que o faturista emitisse a nota,
   * fazendo a barra andar para trás justamente no negócio mais consolidado que
   * existe.
   */
  it('a permuta faturada continua contando — ela é a aprovada que andou', () => {
    const faturada = {
      status: 'invoiced',
      items: [grainItem(1, 'Soja', 30, 148.5), item('input', 2, 115)],
    };
    expect(realizedFrom([...barters, faturada])).toEqual({
      sales: 10 * 115 + 20 * 18.9 + 5 * 320 + 2 * 115,
      sacks: [{ grainId: 1, grainName: 'Soja', sacks: 180 }],
      barters: 3,
    });
  });

  it('sem permuta aprovada, o realizado é zero em todas as unidades', () => {
    expect(realizedFrom([{ status: 'pending', items: [item('input', 1, 10)] }])).toEqual({
      sales: 0,
      sacks: [],
      barters: 0,
    });
  });

  it('meta não definida não vira barra na tela', () => {
    const goals = goalsOf({ targetSales: 5000, targetBarters: null }, realizedFrom(barters), [
      { ...SOJA, targetSacks: null },
    ]);
    expect(goals).toHaveLength(1);
    expect(goals[0]).toMatchObject({ kind: 'sales', target: 5000, realized: 3128, met: false });
    expect(goals[0].ratio).toBeCloseTo(0.6256);
  });

  it('meta atingida acende o aviso, e a barra não passa de 100%', () => {
    const goals = goalsOf({ targetSales: 3000, targetBarters: null }, realizedFrom(barters), [
      { ...SOJA, targetSacks: 150 },
    ]);
    expect(goals.map((goal) => goal.met)).toEqual([true, true]);
    expect(goals[0].ratio).toBe(1);
    expect(anyGoalMet(goals)).toBe(true);
  });

  /**
   * CADA CULTURA TEM A SUA BARRA, e a que ainda não vendeu nada aparece no zero
   * em vez de sumir: o admin lançou a meta, e uma meta sem barra é uma meta que
   * ninguém acompanha.
   */
  it('cada cultura do lançamento vira uma meta de sacas própria', () => {
    const goals = goalsOf({ targetSales: null, targetBarters: null }, realizedFrom(barters), [
      { ...SOJA, targetSacks: 100 },
      { ...MILHO, targetSacks: 500 },
    ]);
    expect(goals).toHaveLength(2);
    expect(goals[0]).toMatchObject({ kind: 'sacks', grainName: 'Soja', realized: 150, met: true });
    expect(goals[1]).toMatchObject({ kind: 'sacks', grainName: 'Milho', realized: 0, met: false });
  });

  /**
   * A frase do fechamento automático. Ela vai para o `closedBy` da versão e fica
   * lá para sempre: é a única coisa que explica, meses depois, por que aquele
   * Barter fechou sem ninguém ter clicado em nada.
   */
  describe('closingReasonOf — por que o Barter fechou sozinho', () => {
    it('nomeia a meta batida e o número dela', () => {
      const goals = goalsOf({ targetSales: 3000, targetBarters: null }, realizedFrom(barters));
      expect(closingReasonOf(goals)).toBe('Automático: meta de vendas atingida (3000.00)');
    });

    it('a meta de permutas é contagem, e sai sem centavos', () => {
      const goals = goalsOf({ targetSales: null, targetBarters: 2 }, realizedFrom(barters));
      expect(closingReasonOf(goals)).toBe('Automático: meta de permutas atingida (2)');
    });

    /**
     * A CULTURA na frase: com soja e milho no mesmo Barter, "meta de sacas
     * atingida" não diz qual delas encheu — e é exatamente isso que alguém vai
     * querer saber ao ler, meses depois, por que o Barter fechou.
     */
    it('a meta de sacas diz de qual cultura ela era', () => {
      const goals = goalsOf({ targetSales: null, targetBarters: null }, realizedFrom(barters), [
        { ...SOJA, targetSacks: 100 },
      ]);
      expect(closingReasonOf(goals)).toBe('Automático: meta de sacas de Soja atingida (100.00)');
    });

    it('meta longe de bater não fecha nada — e não há frase a escrever', () => {
      const goals = goalsOf({ targetSales: 500000, targetBarters: null }, realizedFrom(barters));
      expect(closingReasonOf(goals)).toBeNull();
      expect(closingReasonOf([])).toBeNull();
    });
  });

  /**
   * A lista de "o que soma na meta", vista de fora: é ela que decide se um ato do
   * comitê pode ter acabado de bater a meta.
   */
  it('countsAsRealized responde pela mesma lista da conta do realizado', () => {
    expect(countsAsRealized('approved')).toBe(true);
    expect(countsAsRealized('approvedWithConditions')).toBe(true);
    expect(countsAsRealized('invoiced')).toBe(true);
    expect(countsAsRealized('denied')).toBe(false);
    expect(countsAsRealized('pending')).toBe(false);
    expect(countsAsRealized('draft')).toBe(false);
  });

  describe('isOpenAt — a vigência que TRAVA (a meta só avisa)', () => {
    const hoje = new Date('2026-08-14T12:00:00Z');
    const base = { status: 'active', startsAt: new Date('2026-08-01T00:00:00Z'), endsAt: null };

    it('versão ativa e dentro do período aceita permuta', () => {
      expect(isOpenAt(base, hoje)).toBe(true);
      expect(isOpenAt({ ...base, endsAt: new Date('2026-09-30T00:00:00Z') }, hoje)).toBe(true);
    });

    it('versão encerrada pelo admin não aceita, mesmo dentro do período', () => {
      expect(isOpenAt({ ...base, status: 'closed' }, hoje)).toBe(false);
    });

    it('data de encerramento vencida fecha o Barter', () => {
      expect(isOpenAt({ ...base, endsAt: new Date('2026-08-13T23:59:00Z') }, hoje)).toBe(false);
    });

    it('versão publicada para começar depois ainda não vale', () => {
      expect(isOpenAt({ ...base, startsAt: new Date('2026-08-20T00:00:00Z') }, hoje)).toBe(false);
    });
  });
});
