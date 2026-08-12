import { ThrottlerModule } from '@nestjs/throttler';

/** Janela de contagem: um minuto. */
const WINDOW_MS = 60_000;

function limitFrom(variable: string, fallback: number): number {
  const configured = Number(process.env[variable]);
  return Number.isFinite(configured) && configured > 0 ? configured : fallback;
}

/**
 * Os limites são resolvidos A CADA REQUISIÇÃO, nunca na importação do módulo.
 * Isso não é preciosismo: o `@Throttle` do controller é um decorator, avaliado
 * quando o arquivo é importado — instante em que o ConfigModule ainda não leu
 * o .env. Uma constante de topo de módulo aqui congelaria o padrão e faria o
 * LOGIN_RATE_LIMIT do .env ser ignorado em silêncio. Ver throttling.spec.ts.
 */
export function loginRateLimit(): number {
  return limitFrom('LOGIN_RATE_LIMIT', 10);
}

export function apiRateLimit(): number {
  return limitFrom('API_RATE_LIMIT', 600);
}

/**
 * Limite do /auth/login. É a única rota que um desconhecido pode chamar em
 * volume, e cada chamada é uma tentativa de adivinhar senha — por isso a trava
 * apertada. Ajustável por LOGIN_RATE_LIMIT (os testes e2e sobem o valor porque
 * fazem dezenas de logins legítimos em segundos).
 */
export const loginThrottle = {
  default: { limit: () => loginRateLimit(), ttl: WINDOW_MS },
};

/**
 * Teto geral por IP. Folgado de propósito: o app carrega várias listas de uma
 * vez ao abrir e não pode esbarrar no limite em uso normal — isto existe para
 * conter abuso automatizado, não para moldar o uso legítimo.
 */
export function throttlerModule() {
  return ThrottlerModule.forRoot([{ ttl: WINDOW_MS, limit: () => apiRateLimit() }]);
}
