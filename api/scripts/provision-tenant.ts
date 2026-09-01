import 'dotenv/config';
import { writeFileSync } from 'node:fs';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import { generateProvisionalPassword, hashPassword } from '../src/auth/password.util';
import { passwordProblem } from '../src/auth/password-policy';
import { ROLE, ROLE_LABELS, type Role } from '../src/common/roles';
import { seedDatabase } from '../prisma/seed-data';

/**
 * PROVISIONAMENTO DE UM AMBIENTE DE USO — o banco que os testadores vão abrir.
 *
 *   npm run provision -- --yes
 *   npm run provision -- --yes --out=/caminho/credenciais.json
 *
 * O que ele deixa no banco, e por quê:
 *
 * - **as pessoas e o catálogo**: usuários dos cinco papéis, unidades de
 *   retirada, classes, produtos e a safra vigente com a tabela de preços;
 * - **nada de movimento**: nenhum produtor, nenhuma permuta, nenhum histórico
 *   de preço e nenhuma linha de auditoria.
 *
 * A divisão não é arbitrária — é a linha entre o que o sistema PRECISA para
 * funcionar e o que ele PRODUZ enquanto é usado. Sem safra e sem tabela de
 * preços não existe permuta nova (o consultor recebe a tabela pronta, não a
 * escolhe), então um banco "vazio de verdade" não seria testável: o primeiro
 * consultor a entrar esbarraria em "Barter fechado" e o teste morreria ali. Já
 * as permutas e os produtores do dataset de demonstração são exatamente o que
 * os testadores vão criar — mantê-los faria o trabalho deles se misturar com
 * ficção, e ninguém saberia qual PRM-2026-00x foi de quem.
 *
 * AS SENHAS SÃO SORTEADAS, uma por conta, e aparecem UMA ÚNICA VEZ: na saída
 * deste comando e no arquivo de `--out`. Depois disto elas só existem como
 * hash. O dataset de demonstração usa a mesma senha para todo mundo e ela está
 * publicada no README de um repositório PÚBLICO — o que serve para o simulador
 * na mesa de quem desenvolve e não serve para uma API exposta na internet.
 *
 * Elas nascem DEFINITIVAS, não provisórias: quem recebe o PDF entra e usa. Se
 * o ambiente virar algo mais sério que um teste de uso, o caminho é o
 * `mustChangePassword` do provisionamento normal (ver user-provisioning.service).
 */

const prisma = new PrismaClient({
  adapter: new PrismaPg({
    connectionString: process.env.DATABASE_URL ?? 'postgresql://localhost:5432/barter_dev',
  }),
});

interface Credential {
  fullName: string;
  email: string;
  role: Role;
  roleLabel: string;
  branch: string | null;
  password: string;
}

/**
 * O host do banco que vai ser apagado, sem a senha da URL.
 *
 * Aparece antes de qualquer escrita porque este comando é destrutivo e a
 * DATABASE_URL costuma vir de arquivo (.env) ou do painel do provedor — quem
 * roda não necessariamente lembra para onde ela aponta. Ver o alvo escrito na
 * tela é o que separa "recriei o ambiente de teste" de "apaguei o banco certo
 * por engano".
 */
function targetDescription(): string {
  const url = process.env.DATABASE_URL;
  if (!url) return 'postgresql://localhost:5432/barter_dev (padrão, DATABASE_URL não definida)';
  try {
    const parsed = new URL(url);
    return `${parsed.host}${parsed.pathname}`;
  } catch {
    return '(DATABASE_URL ilegível)';
  }
}

/**
 * Uma senha sorteada que passa na política do próprio sistema.
 *
 * O sorteio é o mesmo do provisionamento pelo app (blocos legíveis, alfabeto
 * sem caracteres ambíguos — é senha para ser DITADA e digitada de um papel). A
 * conferência existe porque a política recusa senha que contenha o nome ou o
 * e-mail do titular: improvável num sorteio, mas o custo de conferir é zero e o
 * de descobrir depois é uma conta que não entra.
 */
function passwordFor(owner: { email: string; fullName: string }): string {
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = generateProvisionalPassword();
    if (!passwordProblem(candidate, owner)) return candidate;
  }
  throw new Error(`Não consegui sortear uma senha válida para ${owner.email}`);
}

/**
 * Apaga o MOVIMENTO, preservando pessoas e catálogo.
 *
 * Reaproveita o dataset de demonstração em vez de reescrever o catálogo aqui:
 * uma segunda cópia dos produtos, das classes e da tabela de preços sairia de
 * sincronia com a primeira no dia em que alguém acrescentasse um insumo, e o
 * ambiente de teste passaria a divergir do que a suíte exercita. A ordem
 * respeita os FKs (filhos primeiro), como no seed.
 */
async function pruneMovement(): Promise<void> {
  await prisma.barterItem.deleteMany();
  await prisma.barterEvent.deleteMany();
  await prisma.barter.deleteMany();
  await prisma.producer.deleteMany();
  await prisma.priceHistoryEntry.deleteMany();
  await prisma.auditLog.deleteMany();
  // As sessões do dataset não existem, mas um banco reprovisionado por cima de
  // um em uso teria: token vivo apontando para senha que acabou de mudar é
  // sessão que não deveria continuar aberta.
  await prisma.accessToken.deleteMany();
}

/**
 * Deixa só o ADMIN e as classes de produto — o ponto de partida de quem vai
 * montar o sistema pelo próprio app.
 *
 * As CLASSES ficam, e isso não é exceção arbitrária: elas são o vocabulário
 * fixo do domínio, e a API não tem como criá-las. `classes.controller.ts` só
 * expõe leitura e o ajuste da REGRA, com o motivo escrito lá — "a lista é fixa;
 * se um dia o negócio ganhar uma classe nova, ela entra por migration". Apagá-
 * las deixaria o sistema sem categorias e sem caminho de volta.
 *
 * A UNIDADE também fica, uma só. É a mesma razão que o `bootstrap-admin.ts` já
 * documenta: cadastrar usuário exige unidade, então um banco com admin e sem
 * nenhuma seria um sistema incapaz de cadastrar a segunda pessoa. Da segunda em
 * diante o admin cria pelo app.
 *
 * O resto — produtos, safras, tabela de preços, os outros usuários, produtores
 * e permutas — sai inteiro, porque tudo isso o admin consegue criar pelas rotas
 * que já existem.
 */
async function keepOnlyAdmin(): Promise<void> {
  await prisma.barterItem.deleteMany();
  await prisma.barterEvent.deleteMany();
  await prisma.barter.deleteMany();
  await prisma.versionPrice.deleteMany();
  await prisma.barterVersion.deleteMany();
  await prisma.season.deleteMany();
  await prisma.priceHistoryEntry.deleteMany();
  await prisma.product.deleteMany();
  await prisma.producer.deleteMany();
  await prisma.auditLog.deleteMany();
  await prisma.accessToken.deleteMany();
  await prisma.user.deleteMany({ where: { role: { not: ROLE.admin } } });

  // Sobra UMA unidade: a do admin, para ele não ficar sem lotação. As demais
  // saem, e o FK dos usuários para unidade é SetNull, então nada quebra.
  const admin = await prisma.user.findFirst({ where: { role: ROLE.admin } });
  if (admin?.unitId) {
    await prisma.unit.deleteMany({ where: { id: { not: admin.unitId } } });
  }
}

/** Sorteia e grava uma senha nova para cada conta, devolvendo o que foi sorteado. */
async function repassword(): Promise<Credential[]> {
  const users = await prisma.user.findMany({ orderBy: { id: 'asc' } });
  const credentials: Credential[] = [];

  for (const user of users) {
    const password = passwordFor(user);
    await prisma.user.update({
      where: { id: user.id },
      data: { password: await hashPassword(password), mustChangePassword: false },
    });
    credentials.push({
      fullName: user.fullName,
      email: user.email,
      role: user.role as Role,
      roleLabel: ROLE_LABELS[user.role as Role] ?? user.role,
      branch: user.branch,
      password,
    });
  }
  return credentials;
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const confirmed = argv.includes('--yes');
  const onlyAdmin = argv.includes('--only-admin');
  const out = argv.find((arg) => arg.startsWith('--out='))?.slice('--out='.length);

  console.log(`Banco alvo: ${targetDescription()}`);

  if (!confirmed) {
    console.error(
      '\nEste comando APAGA o banco inteiro.\n' +
        'Confirme com --yes:\n\n' +
        '  npm run provision -- --yes --out=~/credenciais.json\n' +
        '      pessoas e catálogo prontos, sem movimento\n\n' +
        '  npm run provision -- --yes --only-admin --out=~/credenciais.json\n' +
        '      só o admin e as classes; o resto se cria pelo app\n',
    );
    process.exitCode = 1;
    return;
  }

  console.log('Recriando pessoas e catálogo...');
  await seedDatabase(prisma);

  if (onlyAdmin) {
    console.log('Removendo tudo que o admin consegue criar pelo app...');
    await keepOnlyAdmin();
  } else {
    console.log('Removendo produtores, permutas, histórico e auditoria...');
    await pruneMovement();
  }

  console.log('Sorteando as senhas...');
  const credentials = await repassword();

  const [units, classes, products, prices] = await Promise.all([
    prisma.unit.count(),
    prisma.productClass.count(),
    prisma.product.count(),
    prisma.versionPrice.count(),
  ]);

  console.log(
    `\nPronto: ${credentials.length} conta(s), ${units} unidade(s), ${classes} classes, ` +
      `${products} produtos e ${prices} preços na tabela vigente.\n` +
      (onlyAdmin
        ? 'O admin monta o resto pelo app: unidades, produtos, safra, tabela e usuários.\n'
        : 'Produtores e permutas: 0 — o ambiente começa no zero de movimento.\n'),
  );

  for (const item of credentials) {
    console.log(`  ${item.roleLabel.padEnd(14)} ${item.email.padEnd(34)} ${item.password}`);
  }

  if (out) {
    writeFileSync(out, `${JSON.stringify(credentials, null, 2)}\n`, { mode: 0o600 });
    console.log(`\nCredenciais gravadas em ${out} (permissão 600).`);
    console.log('NÃO versione este arquivo: ele é a única cópia das senhas em texto puro.');
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
