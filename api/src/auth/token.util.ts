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
