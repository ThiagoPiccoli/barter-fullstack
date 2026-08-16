import { isIdle, tokenExpiry, tokenIdleDays, tokenTtlDays } from './token.util';

/**
 * AS DUAS MORTES DE UMA SESSÃO.
 *
 * O prazo absoluto responde "esta sessão já é velha demais"; a inatividade
 * responde "este aparelho ainda está com quem deveria?". Elas são diferentes e
 * precisam continuar sendo: com só a primeira, um celular perdido no sábado
 * segue valendo por até um mês.
 */
describe('validade da sessão', () => {
  const SAVED = { ttl: process.env.TOKEN_TTL_DAYS, idle: process.env.TOKEN_IDLE_DAYS };
  const days = (count: number) => count * 24 * 60 * 60 * 1000;

  beforeEach(() => {
    delete process.env.TOKEN_TTL_DAYS;
    delete process.env.TOKEN_IDLE_DAYS;
  });

  afterAll(() => {
    if (SAVED.ttl === undefined) delete process.env.TOKEN_TTL_DAYS;
    else process.env.TOKEN_TTL_DAYS = SAVED.ttl;
    if (SAVED.idle === undefined) delete process.env.TOKEN_IDLE_DAYS;
    else process.env.TOKEN_IDLE_DAYS = SAVED.idle;
  });

  describe('padrões', () => {
    it('trinta dias de prazo absoluto e sete parada', () => {
      expect(tokenTtlDays()).toBe(30);
      expect(tokenIdleDays()).toBe(7);
    });

    /**
     * A inatividade precisa ser MENOR que o prazo absoluto, senão ela não
     * existe na prática: a sessão morreria de velhice antes de morrer parada.
     */
    it('a inatividade vence antes do prazo absoluto', () => {
      expect(tokenIdleDays()).toBeLessThan(tokenTtlDays());
    });
  });

  describe('configuração', () => {
    it('lê as variáveis a cada chamada, não na importação do módulo', () => {
      process.env.TOKEN_TTL_DAYS = '3';
      process.env.TOKEN_IDLE_DAYS = '1';
      expect(tokenTtlDays()).toBe(3);
      expect(tokenIdleDays()).toBe(1);
    });

    it.each(['0', '-5', 'abc', ''])('valor inválido (%s) cai no padrão', (value) => {
      process.env.TOKEN_IDLE_DAYS = value;
      expect(tokenIdleDays()).toBe(7);
    });
  });

  describe('tokenExpiry', () => {
    it('conta a partir do instante dado', () => {
      const agora = new Date('2026-01-01T00:00:00.000Z');
      expect(tokenExpiry(agora).getTime()).toBe(agora.getTime() + days(30));
    });
  });

  describe('isIdle', () => {
    const agora = new Date('2026-06-10T12:00:00.000Z');

    it('sessão usada agora não está parada', () => {
      expect(isIdle(agora, agora)).toBe(false);
    });

    it('sessão usada ontem continua valendo', () => {
      expect(isIdle(new Date(agora.getTime() - days(1)), agora)).toBe(false);
    });

    it('sessão parada há mais do que o limite morre', () => {
      expect(isIdle(new Date(agora.getTime() - days(8)), agora)).toBe(true);
    });

    /** Exatamente no limite já conta como parada: o limite é o fim, não o começo. */
    it('no limite exato, morre', () => {
      expect(isIdle(new Date(agora.getTime() - days(7)), agora)).toBe(true);
    });
  });
});
