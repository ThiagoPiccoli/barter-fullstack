import type { INestApplication } from '@nestjs/common';
import { setupApp } from './app.setup';

/** O que o setupApp configurou, capturado de um app de mentira. */
interface Configured {
  settings: Record<string, unknown>;
  parsers: Record<string, Record<string, unknown>>;
  middleware: number;
}

function run(): Configured {
  const settings: Record<string, unknown> = {};
  const parsers: Record<string, Record<string, unknown>> = {};
  let middleware = 0;

  const app = {
    setGlobalPrefix: () => undefined,
    enableCors: () => undefined,
    use: () => {
      middleware += 1;
    },
    useBodyParser: (type: string, options: Record<string, unknown>) => {
      parsers[type] = options;
    },
    getHttpAdapter: () => ({
      getInstance: () => ({
        set: (key: string, value: unknown) => {
          settings[key] = value;
        },
      }),
    }),
  } as unknown as INestApplication;

  setupApp(app);
  return { settings, parsers, middleware };
}

/**
 * O `trust proxy` decide de qual IP o limite de requisições acha que a chamada
 * veio. Errar aqui não quebra nada visivelmente — só faz o limite por IP
 * passar a valer para todo mundo somado (atrás de proxy) ou aceitar um
 * X-Forwarded-For forjado (confiando demais). Por isso o teste é do valor
 * aplicado, não do comportamento aparente.
 */
describe('setupApp — trust proxy', () => {
  const SAVED = process.env.TRUST_PROXY;

  afterEach(() => {
    if (SAVED === undefined) delete process.env.TRUST_PROXY;
    else process.env.TRUST_PROXY = SAVED;
  });

  const applied = () => run().settings;

  it('sem a variável, não confia em proxy nenhum', () => {
    delete process.env.TRUST_PROXY;
    expect(applied()['trust proxy']).toBe(false);
  });

  it('número de saltos vira número (o formato recomendado)', () => {
    process.env.TRUST_PROXY = '1';
    expect(applied()['trust proxy']).toBe(1);
  });

  it('aceita true/false explícitos', () => {
    process.env.TRUST_PROXY = 'true';
    expect(applied()['trust proxy']).toBe(true);
    process.env.TRUST_PROXY = 'false';
    expect(applied()['trust proxy']).toBe(false);
  });

  it('texto vira lista de confiança do Express (loopback, sub-rede)', () => {
    process.env.TRUST_PROXY = 'loopback';
    expect(applied()['trust proxy']).toBe('loopback');
    process.env.TRUST_PROXY = '10.0.0.0/8';
    expect(applied()['trust proxy']).toBe('10.0.0.0/8');
  });
});

/**
 * O corpo da requisição tem teto explícito. Se alguém criar o app sem
 * `bodyParser: false`, o parser padrão do Express roda primeiro e ESTE limite
 * deixa de valer em silêncio — por isso o teste fixa o valor aqui, no único
 * lugar que os dois pontos de criação (main.ts e testes e2e) compartilham.
 */
describe('setupApp — corpo da requisição e cabeçalhos', () => {
  it('registra os parsers com limite explícito', () => {
    const { parsers } = run();
    expect(parsers.json).toEqual({ limit: '256kb' });
    expect(parsers.urlencoded).toEqual({ extended: true, limit: '256kb' });
  });

  it('instala os middlewares de segurança e de log', () => {
    // tradutor de erro dos parsers + helmet + log de requisições.
    expect(run().middleware).toBe(3);
  });
});
