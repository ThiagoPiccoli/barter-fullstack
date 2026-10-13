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

/** A linha de pagamento: as sacas da cultura da versão. */
const grainItem = (quantity: number, unitValue: number) => item('grain', quantity, unitValue);

describe('Metas e vigência da versão do Barter', () => {
  const barters = [
    {
      status: 'approved',
      items: [grainItem(100, 148.5), item('input', 10, 115), item('input', 20, 18.9)],
    },
    { status: 'approved', items: [grainItem(50, 148.5), item('input', 5, 320)] },
    // Não entram na conta: uma ainda pode ser negada, a outra já foi.
    { status: 'pending', items: [grainItem(999, 148.5), item('input', 99, 115)] },
    { status: 'denied', items: [grainItem(999, 148.5), item('input', 99, 115)] },
  ];

  const noTargets = { targetSales: null, targetSacks: null, targetBarters: null };

  it('o realizado conta só as permutas aprovadas', () => {
    expect(realizedFrom(barters)).toEqual({
      sales: 10 * 115 + 20 * 18.9 + 5 * 320, // 3128
      sacks: 150,
      barters: 2,
    });
  });

  /**
   * FATURADA CONTINUA REALIZADA. É a mesma permuta aprovada, um posto adiante —
   * e sem isto ela sumiria da meta no dia em que o faturista emitisse a nota,
   * fazendo a barra andar para trás justamente no negócio mais consolidado que
   * existe.
   */
  it('a permuta faturada continua contando — ela é a aprovada que andou', () => {
    const faturada = { status: 'invoiced', items: [grainItem(30, 148.5), item('input', 2, 115)] };
    expect(realizedFrom([...barters, faturada])).toEqual({
      sales: 10 * 115 + 20 * 18.9 + 5 * 320 + 2 * 115,
      sacks: 180,
      barters: 3,
    });
  });

  it('sem permuta aprovada, o realizado é zero em todas as unidades', () => {
    expect(realizedFrom([{ status: 'pending', items: [item('input', 1, 10)] }])).toEqual({
      sales: 0,
      sacks: 0,
      barters: 0,
    });
  });

  it('meta não definida não vira barra na tela', () => {
    const goals = goalsOf({ ...noTargets, targetSales: 5000 }, realizedFrom(barters));
    expect(goals).toHaveLength(1);
    expect(goals[0]).toMatchObject({ kind: 'sales', target: 5000, realized: 3128, met: false });
    expect(goals[0].ratio).toBeCloseTo(0.6256);
  });

  it('meta atingida acende o aviso, e a barra não passa de 100%', () => {
    const goals = goalsOf(
      { ...noTargets, targetSales: 3000, targetSacks: 150 },
      realizedFrom(barters),
    );
    expect(goals.map((goal) => goal.met)).toEqual([true, true]);
    expect(goals[0].ratio).toBe(1);
    expect(anyGoalMet(goals)).toBe(true);
  });

  it('as metas saem na ordem da leitura: vendas, sacas, permutas', () => {
    const goals = goalsOf(
      { targetSales: 10, targetSacks: 10, targetBarters: 10 },
      realizedFrom(barters),
    );
    expect(goals.map((goal) => goal.kind)).toEqual(['sales', 'sacks', 'barters']);
  });

  /**
   * A frase do fechamento automático. Ela vai para o `closedBy` da versão e fica
   * lá para sempre: é a única coisa que explica, meses depois, por que aquele
   * Barter fechou sem ninguém ter clicado em nada.
   */
  describe('closingReasonOf — por que o Barter fechou sozinho', () => {
    it('nomeia a meta batida e o número dela', () => {
      const goals = goalsOf({ ...noTargets, targetSales: 3000 }, realizedFrom(barters));
      expect(closingReasonOf(goals)).toBe('Automático: meta de vendas atingida (3000.00)');
    });

    it('a meta de permutas é contagem, e sai sem centavos', () => {
      const goals = goalsOf({ ...noTargets, targetBarters: 2 }, realizedFrom(barters));
      expect(closingReasonOf(goals)).toBe('Automático: meta de permutas atingida (2)');
    });

    it('a meta de sacas', () => {
      const goals = goalsOf({ ...noTargets, targetSacks: 100 }, realizedFrom(barters));
      expect(closingReasonOf(goals)).toBe('Automático: meta de sacas atingida (100.00)');
    });

    it('meta longe de bater não fecha nada — e não há frase a escrever', () => {
      const goals = goalsOf({ ...noTargets, targetSales: 500000 }, realizedFrom(barters));
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
