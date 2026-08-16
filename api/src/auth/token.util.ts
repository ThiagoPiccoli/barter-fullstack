import { createHash, randomBytes } from 'node:crypto';

/**
 * Tokens de acesso opacos: o cliente recebe o valor cru; o banco guarda só o
 * SHA-256 (vazar o banco não vaza sessões). Logout apaga a linha — revogação
 * real no servidor, mesmo modelo da versão anterior.
 */
export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

const DAY_MS = 24 * 60 * 60 * 1000;

function days(variable: string, fallback: number): number {
  const configured = Number(process.env[variable]);
  return Number.isFinite(configured) && configured > 0 ? configured : fallback;
}

/** Validade máxima da sessão em dias (TOKEN_TTL_DAYS, padrão 30). */
export function tokenTtlDays(): number {
  return days('TOKEN_TTL_DAYS', 30);
}

/**
 * Quantos dias uma sessão sobrevive SEM SER USADA (TOKEN_IDLE_DAYS, padrão 7).
 *
 * As duas datas respondem perguntas diferentes, e é por isso que existem as
 * duas. O prazo absoluto responde "esta sessão já é velha demais"; a
 * inatividade responde "este aparelho ainda está com quem deveria?". Sem a
 * segunda, um celular perdido no sábado continua sendo uma sessão válida por
 * até um mês — e é justamente no aparelho perdido que o prazo longo dói.
 *
 * Sete dias não incomoda quem usa o app na rotina: o consultor que abre o
 * aplicativo durante a semana nunca chega perto do limite.
 */
export function tokenIdleDays(): number {
  return days('TOKEN_IDLE_DAYS', 7);
}

/**
 * Quando uma sessão criada agora deve morrer. O app guarda o token no
 * aparelho entre aberturas, então a sessão precisa ter fim mesmo sem logout.
 */
export function tokenExpiry(from: Date = new Date()): Date {
  return new Date(from.getTime() + tokenTtlDays() * DAY_MS);
}

/** A sessão passou tempo demais parada? */
export function isIdle(lastUsedAt: Date, now: Date = new Date()): boolean {
  return now.getTime() - lastUsedAt.getTime() >= tokenIdleDays() * DAY_MS;
}
