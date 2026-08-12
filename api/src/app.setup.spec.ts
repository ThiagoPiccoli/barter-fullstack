import type { INestApplication } from '@nestjs/common';
import { setupApp } from './app.setup';

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

  /** Sobe o setupApp contra um Express de mentira e devolve o que foi setado. */
  function applied(): Record<string, unknown> {
    const settings: Record<string, unknown> = {};
    const app = {
      setGlobalPrefix: () => undefined,
      enableCors: () => undefined,
      getHttpAdapter: () => ({
        getInstance: () => ({
          set: (key: string, value: unknown) => {
            settings[key] = value;
          },
        }),
      }),
    } as unknown as INestApplication;

    setupApp(app);
    return settings;
  }

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
