import type { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/auth/password.util';

/**
 * Primeiro acesso em PRODUÇÃO. O dataset de demonstração não roda fora de
 * desenvolvimento (ele criaria contas com senha conhecida num servidor
 * público), então o admin inicial vem de variáveis de ambiente — e só quando
 * o banco ainda não tem nenhum usuário.
 *
 * A senha nasce marcada como provisória: o admin é obrigado a trocá-la no
 * primeiro login, de modo que o valor passado no deploy não fica valendo.
 */
export async function bootstrapAdmin(
  prisma: PrismaClient,
): Promise<'created' | 'skipped' | 'missing-env'> {
  const existing = await prisma.user.count();
  if (existing > 0) return 'skipped';

  const email = process.env.ADMIN_EMAIL?.trim();
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password) return 'missing-env';

  await prisma.user.create({
    data: {
      fullName: process.env.ADMIN_NAME?.trim() || 'Administrador',
      email,
      password: await hashPassword(password),
      role: 'admin',
      branch: 'Matriz',
      mustChangePassword: true,
    },
  });
  return 'created';
}
