import {
  BadRequestException,
  Logger,
  PayloadTooLargeException,
  type INestApplication,
} from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import type { Application, ErrorRequestHandler, RequestHandler } from 'express';
import helmet from 'helmet';
import { passwordCostWarning } from './auth/password.util';

/**
 * Teto do corpo da requisição. A maior chamada da API é uma permuta com
 * algumas dezenas de insumos — alguns KB. O limite é explícito para não
 * depender do padrão do Express: uma requisição gigante não deve nem chegar a
 * ser interpretada.
 */
const BODY_LIMIT = '256kb';

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
 * Traduz as falhas do parser de corpo antes que elas virem outra coisa.
 *
 * Corpo grande demais e JSON malformado são erros do CLIENTE, mas nascem no
 * middleware — fora do alcance normal do filtro de exceção. Sem este passo,
 * um deles chegava como 500 ("bug do servidor", registrado como tal) e o
 * outro vazava a mensagem crua do motor de JSON, em inglês, na cara do
 * usuário: "Expected property name or '}' in JSON at position 1".
 *
 * Registrado logo depois dos parsers e ANTES das rotas: pela forma como o
 * Express encadeia tratadores de erro, isto alcança só o que quebra até aqui —
 * erros das rotas seguem para o filtro global, como devem.
 */
function bodyParserErrors(): ErrorRequestHandler {
  return (error: Error & { type?: string }, _request, _response, next) => {
    if (error?.type === 'entity.too.large') {
      return next(new PayloadTooLargeException('O conteúdo enviado é grande demais.'));
    }
    if (error?.type === 'entity.parse.failed') {
      return next(new BadRequestException('O conteúdo enviado não é um JSON válido.'));
    }
    return next(error);
  };
}

/**
 * Uma linha por requisição: método, rota, status e duração. Sem isto não há
 * como responder "o que aconteceu às 14h20?" depois que aconteceu. Nos testes
 * o logger do Nest está desligado, então nada é impresso.
 */
function requestLogger(): RequestHandler {
  const logger = new Logger('HTTP');
  return (request, response, next) => {
    const started = Date.now();
    response.on('finish', () => {
      const line = `${request.method} ${request.originalUrl} ${response.statusCode} — ${Date.now() - started}ms`;
      if (response.statusCode >= 500) logger.error(line);
      else if (response.statusCode >= 400) logger.warn(line);
      else logger.log(line);
    });
    next();
  };
}

/**
 * Configuração de app compartilhada entre o main.ts e os testes e2e, para o
 * servidor de teste se comportar exatamente como o real. Pipes, guard, filtro
 * e interceptor globais são providers do AppModule (valem nos dois contextos).
 *
 * Os dois criadores de app passam `bodyParser: false`; o parser é registrado
 * aqui, com limite explícito.
 */
export function setupApp(app: INestApplication): void {
  const express = app as NestExpressApplication;
  express.useBodyParser('json', { limit: BODY_LIMIT });
  express.useBodyParser('urlencoded', { extended: true, limit: BODY_LIMIT });
  app.use(bodyParserErrors());

  // Cabeçalhos de segurança. `contentSecurityPolicy` fica de fora: a API só
  // devolve JSON (uma CSP não protege nada aqui) e a política padrão do helmet
  // quebraria a página de documentação, que é HTML com estilo embutido.
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(requestLogger());

  // `/health` fica FORA do prefixo com a raiz: sonda de balanceador e de
  // orquestrador aponta para um caminho fixo, e ele não deve mudar quando a
  // API versionar para /api/v2.
  app.setGlobalPrefix('api/v1', { exclude: ['/', '/health'] });
  app.enableCors(corsOptions());
  const server = app.getHttpAdapter().getInstance() as Application;
  server.set('trust proxy', trustProxySetting());

  const warning = passwordCostWarning();
  if (warning) new Logger('Auth').warn(warning);

  const proxyWarning = trustProxyWarning();
  if (proxyWarning) new Logger('Bootstrap').warn(proxyWarning);
}

/**
 * Avisa sobre a configuração de proxy que falha em SILÊNCIO.
 *
 * Sem TRUST_PROXY, o Express enxerga o IP de quem fala direto com ele — atrás
 * de um nginx ou de um PaaS, isso é o IP do PROXY, o mesmo para todo mundo. O
 * limitador de requisições continua funcionando, contando certinho... o mundo
 * inteiro como um cliente só. As dez tentativas de login por minuto passam a
 * ser dez para TODOS os usuários somados: o primeiro a errar a senha tira os
 * outros do ar, e a proteção contra adivinhação deixa de existir.
 *
 * Nada nesse arranjo produz erro — nem no log, nem na resposta. O aviso na
 * subida é a única chance de alguém perceber, e por isso ele nasce junto com o
 * de PASSWORD_COST: os dois são configurações cujo defeito só aparece no dia em
 * que importa.
 */
function trustProxyWarning(): string | null {
  if (process.env.NODE_ENV !== 'production') return null;
  if (process.env.TRUST_PROXY?.trim()) return null;
  return (
    'TRUST_PROXY não definida: o limite por IP vai contar o IP de quem fala direto com a API. ' +
    'Se houver proxy na frente (nginx, Cloudflare, PaaS), todos os usuários somados disputam o ' +
    'mesmo limite — defina o NÚMERO DE SALTOS (ex.: TRUST_PROXY=1). Sem proxy, ignore este aviso.'
  );
}
