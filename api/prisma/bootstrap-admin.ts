import type { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/auth/password.util';
import { passwordProblem } from '../src/auth/password-policy';
import { ROLE } from '../src/common/roles';
import { normalizeName } from '../src/seasons/product-name';

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
): Promise<
  { status: 'created' | 'skipped' | 'missing-env' } | { status: 'weak-password'; reason: string }
> {
  const existing = await prisma.user.count();
  if (existing > 0) return { status: 'skipped' };

  const email = process.env.ADMIN_EMAIL?.trim();
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password) return { status: 'missing-env' };

  const fullName = process.env.ADMIN_NAME?.trim() || 'Administrador';

  // A MESMA política de todas as outras senhas do sistema, aplicada à primeira
  // de todas — a que abre a conta com mais poder, num servidor exposto, com o
  // valor que alguém digitou às pressas no painel do provedor. Recusar deixa o
  // banco sem admin, e é isso mesmo: um sistema sem administrador espera; um
  // administrador com senha `admin123` já está comprometido e ninguém sabe.
  const problem = passwordProblem(password, { email, fullName });
  if (problem) return { status: 'weak-password', reason: problem };

  // A PRIMEIRA UNIDADE nasce junto com o primeiro admin, e não por acaso: o
  // cadastro de qualquer usuário exige uma unidade, então um banco com admin e
  // sem unidade nenhuma seria um sistema que não consegue cadastrar a segunda
  // pessoa. Ela vem sem gerente — designar o responsável é o passo seguinte,
  // depois de o admin provisionar um.
  const matriz = await prisma.unit.create({
    data: { name: 'Matriz', nameKey: normalizeName('Matriz'), city: 'Sede' },
  });

  await prisma.user.create({
    data: {
      fullName,
      email,
      password: await hashPassword(password),
      role: ROLE.admin,
      unitId: matriz.id,
      branch: matriz.name,
      mustChangePassword: true,
    },
  });
  return { status: 'created' };
}
