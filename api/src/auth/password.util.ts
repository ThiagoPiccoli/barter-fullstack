import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb) as (
  password: string,
  salt: string,
  keylen: number,
) => Promise<Buffer>;

/**
 * Hash de senha com scrypt do Node (sem dependência nativa).
 * Formato armazenado: `scrypt:<salt-hex>:<hash-hex>`.
 */
export async function hashPassword(plain: string): Promise<string> {
  const salt = randomBytes(16).toString('hex');
  const hash = await scrypt(plain, salt, 64);
  return `scrypt:${salt}:${hash.toString('hex')}`;
}

export async function verifyPassword(plain: string, stored: string): Promise<boolean> {
  const [scheme, salt, hashHex] = stored.split(':');
  if (scheme !== 'scrypt' || !salt || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = await scrypt(plain, salt, expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
