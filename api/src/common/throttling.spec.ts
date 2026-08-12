import { apiRateLimit, loginRateLimit, loginThrottle } from './throttling';

/**
 * Regressão de um bug silencioso: os limites eram constantes de topo de
 * módulo, avaliadas quando o arquivo é IMPORTADO — antes do ConfigModule ler
 * o .env. Quem configurasse LOGIN_RATE_LIMIT no .env ficava com o padrão sem
 * nenhum aviso, e os testes não pegavam porque o script e2e injeta as
 * variáveis via dotenv-cli (isto é, já no ambiente do processo).
 *
 * Este arquivo reproduz aquela ordem de propósito: o `import` acima roda com
 * o ambiente vazio, e só depois cada teste define a variável. Se alguém
 * voltar a congelar o valor na importação, os testes abaixo falham.
 */
describe('limites de requisição', () => {
  const SAVED = { login: process.env.LOGIN_RATE_LIMIT, api: process.env.API_RATE_LIMIT };

  beforeEach(() => {
    delete process.env.LOGIN_RATE_LIMIT;
    delete process.env.API_RATE_LIMIT;
  });

  afterAll(() => {
    if (SAVED.login === undefined) delete process.env.LOGIN_RATE_LIMIT;
    else process.env.LOGIN_RATE_LIMIT = SAVED.login;
    if (SAVED.api === undefined) delete process.env.API_RATE_LIMIT;
    else process.env.API_RATE_LIMIT = SAVED.api;
  });

  it('lê a variável depois da importação do módulo', () => {
    process.env.LOGIN_RATE_LIMIT = '42';
    process.env.API_RATE_LIMIT = '4242';

    expect(loginRateLimit()).toBe(42);
    expect(apiRateLimit()).toBe(4242);
  });

  it('sem a variável, vale o padrão', () => {
    expect(loginRateLimit()).toBe(10);
    expect(apiRateLimit()).toBe(600);
  });

  it.each(['', 'dez', '0', '-5', 'NaN'])(
    'valor inválido (%p) cai no padrão em vez de zerar o limite',
    (value) => {
      process.env.LOGIN_RATE_LIMIT = value;
      expect(loginRateLimit()).toBe(10);
    },
  );

  /**
   * O `@Throttle` do AuthController é um decorator: ele guarda o que estiver
   * neste objeto no momento da importação. Passar um número aqui é o que
   * causava o bug — tem que ser um resolvedor, que o ThrottlerGuard chama a
   * cada requisição.
   */
  it('o @Throttle do login recebe um resolvedor, não um número congelado', () => {
    expect(typeof loginThrottle.default.limit).toBe('function');

    process.env.LOGIN_RATE_LIMIT = '7';
    expect(loginThrottle.default.limit()).toBe(7);
  });
});
