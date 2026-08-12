import type { INestApplication } from '@nestjs/common';
import type { Application } from 'express';

/**
 * Origens permitidas no CORS. Em desenvolvimento fica liberado (o app roda de
 * emulador, simulador e Flutter web em portas variadas); em produção só passa
 * o que estiver em CORS_ORIGINS, e sem a variável nada de outra origem entra.
 *
 * Isso não afeta o app mobile: requisições nativas não mandam `Origin`, então
 * elas seguem funcionando com a política fechada — quem depende disto é a
 * versão web.
 */
function corsOptions(): Parameters<INestApplication['enableCors']>[0] {
  const configured = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  if (configured.length > 0) return { origin: configured };
  return process.env.NODE_ENV === 'production' ? { origin: false } : {};
}

/**
 * Quantos proxies existem na frente da API (TRUST_PROXY). O limite de
 * requisições conta por IP, e o IP que o Express enxerga sem esta
 * configuração é o do PROXY: atrás de nginx, Cloudflare ou de um PaaS, o
 * mundo inteiro viraria um cliente só — as dez tentativas de login por minuto
 * seriam dez para TODOS os usuários somados, e a proteção por IP deixaria de
 * existir.
 *
 * O padrão é não confiar em ninguém, e é de propósito: confiar no
 * X-Forwarded-For de quem fala direto com a API deixaria qualquer um forjar o
 * próprio IP e passar por baixo do limite. Use o NÚMERO DE SALTOS até a API
 * (`TRUST_PROXY=1` para um nginx à frente) em vez de `true`, que aceita a
 * cadeia inteira.
 */
function trustProxySetting(): number | boolean | string {
  const configured = process.env.TRUST_PROXY?.trim();
  if (!configured) return false;
  if (configured === 'true') return true;
  if (configured === 'false') return false;

  const hops = Number(configured);
  // Não sendo número, vale como lista de IPs/sub-redes confiáveis do Express
  // (ex.: 'loopback', '10.0.0.0/8').
  return Number.isInteger(hops) && hops >= 0 ? hops : configured;
}

/**
 * Configuração de app compartilhada entre o main.ts e os testes e2e, para o
 * servidor de teste se comportar exatamente como o real. Pipes, guard e
 * interceptor globais são providers do AppModule (valem nos dois contextos).
 */
export function setupApp(app: INestApplication): void {
  app.setGlobalPrefix('api/v1', { exclude: ['/'] });
  app.enableCors(corsOptions());
  const server = app.getHttpAdapter().getInstance() as Application;
  server.set('trust proxy', trustProxySetting());
}
