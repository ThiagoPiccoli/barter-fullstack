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

/** Validade da sessão em dias (TOKEN_TTL_DAYS, padrão 30). */
export function tokenTtlDays(): number {
  const configured = Number(process.env.TOKEN_TTL_DAYS);
  return Number.isFinite(configured) && configured > 0 ? configured : 30;
}

/**
 * Quando uma sessão criada agora deve morrer. O app guarda o token no
 * aparelho entre aberturas, então a sessão precisa ter fim mesmo sem logout.
 */
export function tokenExpiry(from: Date = new Date()): Date {
  return new Date(from.getTime() + tokenTtlDays() * 24 * 60 * 60 * 1000);
}
