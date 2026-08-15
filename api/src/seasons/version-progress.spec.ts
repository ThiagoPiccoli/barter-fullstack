import { anyGoalMet, goalsOf, isOpenAt, realizedFrom } from './version-progress';

const item = (kind: string, quantity: number, unitValue: number) => ({
  kind,
  quantity,
  unitValue,
});

describe('Metas e vigência da versão do Barter', () => {
  const barters = [
    {
      status: 'approved',
      items: [item('grain', 100, 148.5), item('input', 10, 115), item('input', 20, 18.9)],
    },
    { status: 'approved', items: [item('grain', 50, 148.5), item('input', 5, 320)] },
    // Não entram na conta: uma ainda pode ser negada, a outra já foi.
    { status: 'pending', items: [item('grain', 999, 148.5), item('input', 99, 115)] },
    { status: 'denied', items: [item('grain', 999, 148.5), item('input', 99, 115)] },
  ];

  it('o realizado conta só as permutas aprovadas', () => {
    expect(realizedFrom(barters)).toEqual({
      sales: 10 * 115 + 20 * 18.9 + 5 * 320, // 3128
      sacks: 150,
      barters: 2,
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
    const goals = goalsOf(
      { targetSales: 5000, targetSacks: null, targetBarters: null },
      realizedFrom(barters),
    );
    expect(goals).toHaveLength(1);
    expect(goals[0]).toMatchObject({ kind: 'sales', target: 5000, realized: 3128, met: false });
    expect(goals[0].ratio).toBeCloseTo(0.6256);
  });

  it('meta atingida acende o aviso, e a barra não passa de 100%', () => {
    const goals = goalsOf(
      { targetSales: 3000, targetSacks: 150, targetBarters: null },
      realizedFrom(barters),
    );
    expect(goals.map((goal) => goal.met)).toEqual([true, true]);
    expect(goals[0].ratio).toBe(1);
    expect(anyGoalMet(goals)).toBe(true);
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
