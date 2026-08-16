import { randomBytes, randomInt, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb) as (
  password: string,
  salt: string,
  keylen: number,
  options: { N: number; r: number; p: number; maxmem: number },
) => Promise<Buffer>;

/**
 * Custo do scrypt. `r` e `p` seguem a combinação recomendada pela OWASP
 * (N=2^16, r=8, p=2 — cerca de 170ms e 64MB por verificação).
 *
 * O expoente é ajustável por PASSWORD_COST porque a suíte e2e faz dezenas de
 * logins em segundos e não pode pagar 170ms em cada um (ver .env.test). Baixar
 * isto em produção enfraquece TODAS as senhas novas, então a subida do
 * servidor avisa quando o valor está abaixo do padrão seguro.
 */
const SAFE_COST = 16;
const KEY_LENGTH = 64;

export function passwordCost(): number {
  const configured = Number(process.env.PASSWORD_COST);
  return Number.isInteger(configured) && configured >= 10 && configured <= 20
    ? configured
    : SAFE_COST;
}

/** Avisa quando a configuração de custo está abaixo do padrão seguro. */
export function passwordCostWarning(): string | null {
  const cost = passwordCost();
  if (cost >= SAFE_COST) return null;
  return `PASSWORD_COST=${cost} está abaixo do padrão seguro (${SAFE_COST}): as senhas novas ficam mais fáceis de quebrar. Use este valor apenas em testes.`;
}

interface ScryptParams {
  N: number;
  r: number;
  p: number;
}

function paramsFor(cost: number): ScryptParams {
  return { N: 2 ** cost, r: 8, p: 2 };
}

/** `maxmem` precisa acompanhar N e r, senão o próprio Node recusa o cálculo. */
function derive(plain: string, salt: string, params: ScryptParams): Promise<Buffer> {
  return scrypt(plain, salt, KEY_LENGTH, {
    ...params,
    maxmem: 256 * params.N * params.r,
  });
}

/**
 * Hash de senha com scrypt do Node (sem dependência nativa).
 *
 * Formato armazenado: `scrypt:<N>:<r>:<p>:<salt-hex>:<hash-hex>`. Os
 * PARÂMETROS ficam gravados junto — sem eles não dá para aumentar o custo mais
 * tarde sem invalidar todas as senhas já cadastradas. Hashes no formato antigo
 * (`scrypt:<salt>:<hash>`, defaults do Node) continuam válidos e são
 * reescritos no primeiro login bem-sucedido (ver needsRehash).
 */
export async function hashPassword(plain: string): Promise<string> {
  const params = paramsFor(passwordCost());
  const salt = randomBytes(16).toString('hex');
  const hash = await derive(plain, salt, params);
  return `scrypt:${params.N}:${params.r}:${params.p}:${salt}:${hash.toString('hex')}`;
}

/** Lê salt e parâmetros de um hash armazenado, nos dois formatos. */
function parseStored(stored: string): { salt: string; hash: string; params: ScryptParams } | null {
  const parts = stored.split(':');
  if (parts[0] !== 'scrypt') return null;

  // Formato antigo: scrypt:<salt>:<hash>, gerado com os defaults do Node.
  if (parts.length === 3) {
    const [, salt, hash] = parts;
    return salt && hash ? { salt, hash, params: { N: 16384, r: 8, p: 1 } } : null;
  }

  if (parts.length === 6) {
    const [, n, r, p, salt, hash] = parts;
    const params = { N: Number(n), r: Number(r), p: Number(p) };
    const valid =
      Number.isInteger(params.N) &&
      Number.isInteger(params.r) &&
      Number.isInteger(params.p) &&
      params.N > 1 &&
      params.r > 0 &&
      params.p > 0;
    return valid && salt && hash ? { salt, hash, params } : null;
  }

  return null;
}

export async function verifyPassword(plain: string, stored: string): Promise<boolean> {
  const parsed = parseStored(stored);
  if (!parsed) return false;
  const expected = Buffer.from(parsed.hash, 'hex');
  if (expected.length === 0) return false;
  const actual = await derive(plain, parsed.salt, parsed.params);
  const trimmed = actual.subarray(0, expected.length);
  return trimmed.length === expected.length && timingSafeEqual(trimmed, expected);
}

/**
 * Este hash foi gerado com custo menor que o atual? Serve para reescrever a
 * senha em silêncio no login: quem entrou com um hash antigo sai com um hash
 * no custo de hoje, sem precisar trocar de senha.
 */
export function needsRehash(stored: string): boolean {
  const parsed = parseStored(stored);
  if (!parsed) return true;
  const target = paramsFor(passwordCost());
  return parsed.params.N < target.N || parsed.params.r < target.r || parsed.params.p < target.p;
}

/**
 * Trabalho descartado, com o mesmo custo de uma verificação real. O login
 * chama isto quando o e-mail não existe: sem ele a resposta volta rápido
 * demais e o tempo denuncia quais e-mails estão cadastrados.
 */
export async function burnPasswordTime(): Promise<void> {
  await derive('', '0'.repeat(32), paramsFor(passwordCost()));
}

/**
 * Alfabeto sem caracteres confundíveis (0/O, 1/I/L): a senha provisória é
 * DITADA pelo admin ao consultor, por telefone ou no balcão.
 */
const UNAMBIGUOUS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/**
 * Senha provisória de primeira entrada — uma por consultor, aleatória.
 *
 * Um valor fixo compartilhado (o antigo '123456') deixava toda conta recém
 * criada aberta para quem soubesse o e-mail: bastava entrar antes do titular e
 * definir a senha definitiva, e o admin não tinha como retomar a conta. A
 * senha nasce diferente a cada consultor, é mostrada uma única vez a quem
 * criou o cadastro e morre na primeira troca.
 *
 * TRÊS BLOCOS, e não dois. O sorteio de dois blocos já era forte (cerca de 40
 * bits), mas produzia 9 caracteres — abaixo do piso que a política exige de
 * quem digita a sua (ver MIN_PASSWORD_LENGTH). Um sistema que gera uma senha
 * que ele mesmo recusaria é uma contradição que alguém vai encontrar do jeito
 * ruim. O bloco a mais custa quatro letras a quem dita no telefone e sobe o
 * sorteio para cerca de 59 bits.
 */
export function generateProvisionalPassword(): string {
  const pick = () => UNAMBIGUOUS[randomInt(UNAMBIGUOUS.length)];
  const block = (size: number) => Array.from({ length: size }, pick).join('');
  return `${block(4)}-${block(4)}-${block(4)}`;
}
