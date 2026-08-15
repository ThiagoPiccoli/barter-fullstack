import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import { generateProvisionalPassword, hashPassword } from '../src/auth/password.util';

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
    select: { id: true, email: true, fullName: true, role: true, mustChangePassword: true },
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
    const pending = user.mustChangePassword ? '  (senha provisória pendente de troca)' : '';
    console.log(`  [${user.role.padEnd(10)}] ${user.email}  — ${user.fullName}${pending}`);
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

  if (chosen !== undefined && chosen.length < 6) {
    console.error('A senha precisa ter ao menos 6 caracteres.');
    return 1;
  }

  const password = chosen ?? generateProvisionalPassword();
  await prisma.$transaction([
    prisma.user.update({
      where: { id: user.id },
      data: { password: await hashPassword(password), mustChangePassword: true },
    }),
    prisma.accessToken.deleteMany({ where: { userId: user.id } }),
  ]);

  console.log(`\n  Conta ...... ${user.email} (${user.role})`);
  console.log(`  Senha ...... ${password}`);
  console.log('\nSenha PROVISÓRIA: será exigida uma troca no primeiro login.');
  console.log('As sessões que estavam abertas nesta conta foram encerradas.\n');
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
