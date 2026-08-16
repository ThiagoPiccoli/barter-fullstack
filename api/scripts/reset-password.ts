import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import { CLEARED_LOCKOUT, isLocked } from '../src/auth/lockout';
import { generateProvisionalPassword, hashPassword } from '../src/auth/password.util';
import { passwordProblem } from '../src/auth/password-policy';

/**
 * Redefinição de senha PELA LINHA DE COMANDO — a saída de emergência do
 * sistema.
 *
 * Existe por causa do admin. O reset de consultor é feito pelo próprio admin
 * dentro do app, mas o admin não tem ninguém acima dele: perdida a senha da
 * única conta de administração, não sobra nenhum caminho pela aplicação, e o
 * provisionamento inicial (bootstrap-admin) só roda com o banco vazio. Quem
 * tem acesso ao servidor precisa conseguir voltar a entrar sem apagar o banco.
 *
 *   npm run password:reset                      # lista as contas
 *   npm run password:reset -- admin@empresa.com # sorteia uma senha provisória
 *   npm run password:reset -- admin@empresa.com --password=minha-senha
 *
 * A senha definida aqui é sempre PROVISÓRIA: quem entrar com ela é obrigado a
 * trocá-la, então o valor que passou pelo terminal não fica valendo. Todas as
 * sessões abertas da conta são encerradas.
 */

const prisma = new PrismaClient({
  adapter: new PrismaPg({
    connectionString: process.env.DATABASE_URL ?? 'postgresql://localhost:5432/barter_dev',
  }),
});

function parseArgs(argv: string[]): { email?: string; password?: string } {
  const email = argv.find((arg) => !arg.startsWith('--'));
  const password = argv.find((arg) => arg.startsWith('--password='))?.slice('--password='.length);
  return { email, password };
}

async function listAccounts(): Promise<void> {
  const users = await prisma.user.findMany({
    orderBy: [{ role: 'asc' }, { id: 'asc' }],
    select: {
      id: true,
      email: true,
      fullName: true,
      role: true,
      mustChangePassword: true,
      // A trava aparece na listagem porque é ela que explica o sintoma que traz
      // alguém até este script: "a senha está certa e não entra".
      lockedUntil: true,
    },
  });

  if (users.length === 0) {
    console.log(
      'Nenhum usuário no banco. Defina ADMIN_EMAIL e ADMIN_PASSWORD e suba o servidor\n' +
        'para provisionar o primeiro acesso (ver prisma/bootstrap-admin.ts).',
    );
    return;
  }

  console.log('Contas cadastradas:\n');
  for (const user of users) {
    const marks = [
      user.mustChangePassword ? 'senha provisória pendente de troca' : null,
      isLocked(user) ? 'BLOQUEADA por tentativas erradas' : null,
    ].filter(Boolean);
    const suffix = marks.length > 0 ? `  (${marks.join('; ')})` : '';
    console.log(`  [${user.role.padEnd(10)}] ${user.email}  — ${user.fullName}${suffix}`);
  }
  console.log('\nPara redefinir:  npm run password:reset -- <e-mail>');
}

async function resetFor(email: string, chosen?: string): Promise<number> {
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    console.error(`Nenhuma conta com o e-mail "${email}".`);
    console.error('Rode sem argumentos para ver a lista de contas.');
    return 1;
  }

  // A senha escolhida à mão passa pela MESMA regra do resto do sistema (ver
  // src/auth/password-policy.ts). Antes daqui saía um piso próprio, de seis
  // caracteres — e a exceção mais perigosa é justamente esta, que roda como
  // root no servidor e costuma ser usada para a conta do admin.
  const problem = chosen === undefined ? null : passwordProblem(chosen, user);
  if (problem) {
    console.error(`${problem}.`);
    return 1;
  }

  const password = chosen ?? generateProvisionalPassword();
  const wasLocked = isLocked(user);

  // CLEARED_LOCKOUT junto com a senha, e não como um segundo passo: esta é a
  // saída de emergência do sistema, e ela precisa DEVOLVER O ACESSO. A trava
  // por tentativas erradas é checada no login antes da senha, então sem isto o
  // script entregava uma senha nova que continuava sendo recusada por até
  // quinze minutos — justamente na conta do admin, que é quem não tem ninguém
  // acima para destravá-la.
  await prisma.$transaction([
    prisma.user.update({
      where: { id: user.id },
      data: {
        password: await hashPassword(password),
        mustChangePassword: true,
        ...CLEARED_LOCKOUT,
      },
    }),
    prisma.accessToken.deleteMany({ where: { userId: user.id } }),
  ]);

  console.log(`\n  Conta ...... ${user.email} (${user.role})`);
  console.log(`  Senha ...... ${password}`);
  console.log('\nSenha PROVISÓRIA: será exigida uma troca no primeiro login.');
  console.log('As sessões que estavam abertas nesta conta foram encerradas.');
  if (wasLocked) {
    console.log('A conta estava BLOQUEADA por tentativas erradas — o bloqueio foi removido.');
  }
  console.log('');
  return 0;
}

async function main(): Promise<number> {
  const { email, password } = parseArgs(process.argv.slice(2));
  if (!email) {
    await listAccounts();
    return 0;
  }
  return resetFor(email, password);
}

main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => void prisma.$disconnect());
