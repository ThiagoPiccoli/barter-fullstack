import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { SEED_PASSWORD, seedDatabase } from '../prisma/seed-data';
import { AppModule } from '../src/app.module';
import { setupApp } from '../src/app.setup';
import { PrismaService } from '../src/prisma/prisma.service';

/**
 * Sobe a aplicação real (mesmos guards/pipes/interceptor globais do
 * AppModule + setupApp compartilhado com o main.ts). O banco é o PostgreSQL de
 * teste apontado pela DATABASE_URL — o `barter_test` do `.env.test` na máquina
 * de quem desenvolve, e o serviço do runner no CI.
 */
export async function createTestApp(): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  // `bodyParser: false` espelha o main.ts: quem registra o parser (com limite
  // explícito) é o setupApp, e o servidor de teste precisa do mesmo.
  const app = moduleRef.createNestApplication({ logger: false, bodyParser: false });
  setupApp(app);
  await app.init();
  // O servidor PASSA A ESCUTAR aqui, e não no supertest.
  //
  // `app.init()` monta a aplicação mas não abre porta. Sem porta aberta, cada
  // `request(app.getHttpServer())` do supertest chama `listen(0)` no MESMO
  // objeto de servidor e guarda o endereço que voltar. Enquanto as chamadas são
  // uma de cada vez, isso funciona por acidente.
  //
  // Elas não são. O padrão que as specs usam —
  // `request(app.getHttpServer()).get(rota).set('Authorization', await asUser(X))`
  // — tem um `await` DENTRO da montagem do pedido: o `asUser` dispara um
  // segundo pedido (o login) enquanto o primeiro já pegou o servidor. As duas
  // chamadas de `listen(0)` se cruzam, uma delas enxerga o servidor ainda sem
  // endereço, e o pedido sai para um servidor que ainda não tem as rotas do
  // Nest penduradas. O que volta é o 404 do Express, de corpo vazio — nada a
  // ver com a rota pedida, e por isso a falha aparecia longe da causa.
  //
  // Era daí que vinha a intermitência da suíte: o mesmo arquivo passava sozinho
  // e quebrava em dezenas de casos quando rodava junto dos outros, variando de
  // execução para execução conforme o tempo caía. Com a porta já aberta, o
  // supertest só lê o endereço e não há corrida.
  await app.listen(0);
  return app;
}

/**
 * Restaura o dataset de demonstração (apaga tudo e re-semeia) com os MESMOS
 * ids a cada teste.
 *
 * `deleteMany()` não volta a sequência do autoincrement: sem reiniciá-la, os
 * ids cresceriam a cada spec em vez de recomeçar em 1, e os testes que fixam id
 * do seed (produtor 1 = Antônio, produto 5 = NPK) passariam a apontar para
 * outro registro. Por isso as sequências do Postgres são zeradas ANTES de
 * semear — `RESTART IDENTITY` num TRUNCATE de todas as tabelas faria o mesmo,
 * mas exigiria listá-las na ordem das FKs, que é o que o seed já sabe fazer.
 */
export async function resetDb(app: INestApplication): Promise<void> {
  const prisma = app.get(PrismaService);
  await seedDatabase(prisma);
  await restartSequences(prisma);
  await seedDatabase(prisma);
}

/** Todas as sequências de id do schema public voltam a 1. */
async function restartSequences(prisma: PrismaService): Promise<void> {
  const sequences = await prisma.$queryRawUnsafe<{ sequencename: string }[]>(
    `SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'`,
  );
  for (const { sequencename } of sequences) {
    await prisma.$executeRawUnsafe(`ALTER SEQUENCE "${sequencename}" RESTART WITH 1`);
  }
}

/**
 * A senha do dataset de demonstração, reexportada para as specs.
 *
 * Vem do seed e não de um literal repetido: enquanto cada spec escrevia
 * `'123456'` na mão, trocar a senha de demonstração exigia caçar o valor por
 * oito arquivos — e um esquecido só aparece como um 400 misterioso.
 */
export { SEED_PASSWORD } from '../prisma/seed-data';

/**
 * Loga com a senha do seed e devolve o token Bearer.
 *
 * O login é CONFERIDO aqui, e não lido às cegas. Sem esta checagem, um login
 * que não deu 200 devolvia `response.body.data` indefinido e a spec quebrava
 * lá adiante com `Cannot read properties of undefined (reading 'token')` —
 * uma pilha que aponta para esta linha e não diz nada sobre o motivo. Quando
 * isso acontece em cinquenta testes de uma vez, o que está na tela é cinquenta
 * cópias do mesmo TypeError, e o status que explicaria tudo (429 do limite de
 * login, 401 de seed que não rodou, 500 do banco) nunca chega a ser visto.
 */
export async function loginAs(app: INestApplication, email: string): Promise<string> {
  const response = await request(app.getHttpServer())
    .post('/api/v1/auth/login')
    .send({ email, password: SEED_PASSWORD });
  const token = (response.body as { data?: { token?: string } }).data?.token;
  if (!token) {
    throw new Error(
      `Login de ${email} falhou: HTTP ${response.status} — ${JSON.stringify(response.body)}`,
    );
  }
  return token;
}

export const ADMIN = 'admin@agrobarter.com.br';
export const JOAO = 'joao.silva@agrobarter.com.br';
export const ANA = 'ana.ferreira@agrobarter.com.br';

/**
 * Roberto divide com o João o atendimento de Joaquim Tavares — o produtor
 * COMPARTILHADO do dataset. Ele está aqui para os testes poderem olhar a mesma
 * carteira pelos dois lados: um produtor em duas carteiras é a coisa que um
 * consultor só não consegue demonstrar.
 */
export const ROBERTO = 'roberto.souza@agrobarter.com.br';

/** Os ids dos consultores que os testes de carteira nomeiam. */
export const CONSULTANT = { joao: 2, ana: 3, roberto: 4 } as const;

/* Retaguarda (um por papel novo). */
export const GERENTE = 'gerente@agrobarter.com.br';
export const COMITE = 'comite@agrobarter.com.br';
export const FATURISTA = 'faturista@agrobarter.com.br';

/**
 * O EMISSOR — o posto que a cédula ganhou: ele confere o que o consultor
 * preencheu, emite o título, colhe as assinaturas e o leva a registro.
 *
 * É o último da esteira, e o mais estreito no que enxerga: um degrau adiante do
 * faturista.
 */
export const EMISSOR = 'emissor@agrobarter.com.br';

/**
 * O SEGUNDO gerente do dataset — Gustavo, das filiais do sul.
 *
 * Ele existe para os testes poderem perguntar a coisa que um gerente só não
 * responde: "o gerente da outra praça consegue opinar sobre esta permuta?".
 */
export const GERENTE_SUL = 'gerente.sul@agrobarter.com.br';

/** Os papéis de retaguarda, para varrer todos. */
export const BACK_OFFICE = [GERENTE, COMITE, FATURISTA, EMISSOR];

/**
 * Os ids dos dois gerentes do dataset.
 *
 * Beatriz gerencia João e Ana; Gustavo, Roberto, Maria e Lucas. É o TIME que
 * decide para quem a permuta vai — a unidade de retirada não tem relação com
 * isso.
 */
export const MANAGER = { beatriz: 7, gustavo: 10 } as const;

/**
 * As unidades do dataset, na ordem em que o seed as cria. São LOCAIS de
 * retirada: não têm responsável e não roteiam nada.
 */
export const UNIT = {
  matriz: 1,
  filial02: 2,
  filial04: 3,
  filial18: 4,
  filial24: 5,
  filial34: 6,
} as const;

/**
 * ANEXA UMA NOTA FISCAL à permuta — o que `POST /barters/:code/invoice` passou a
 * exigir antes de faturar.
 *
 * Ele mora aqui, e não em cada spec, porque a exigência tocou TODOS os testes
 * que faturam: a nota é a origem da dívida que a cédula afirma, e uma permuta
 * "faturada" sem nota nenhuma é um faturamento sem prova. Repeti-lo em seis
 * arquivos faria a próxima mudança do upload custar seis edições.
 *
 * O ARQUIVO é um PDF mínimo de mentira (quatro bytes com o cabeçalho certo): o
 * que a rota confere é o tipo declarado e o tamanho, e o conteúdo só volta em
 * download. Um PDF de verdade aqui seria peso sem pergunta nova respondida.
 */
export async function attachInvoice(
  app: INestApplication,
  auth: string,
  code: string,
  fields: { number?: string; series?: string; duplicateNumber?: string } = {},
) {
  return request(app.getHttpServer())
    .post(`/api/v1/barters/${code}/invoices`)
    .set('Authorization', auth)
    .field('number', fields.number ?? '55.318')
    .field('series', fields.series ?? '1')
    .field('duplicateNumber', fields.duplicateNumber ?? '55.318-A')
    .attach('file', Buffer.from('%PDF-1.4\n%%EOF\n'), {
      filename: 'nota.pdf',
      contentType: 'application/pdf',
    });
}

/**
 * PREENCHE A CÉDULA com o que é do CONSULTOR — o que o encaminhamento passou a
 * exigir.
 *
 * Ele mora aqui, e não em cada spec, pelo mesmo motivo de `attachInvoice`: a
 * exigência tocou TODA suíte que encaminha uma permuta nova. A cédula é coletada
 * na visita, com o produtor por perto, e não semanas depois — mas para um teste
 * que quer chegar ao gerente ela é preâmbulo, e repeti-lo em oito arquivos faria
 * a próxima mudança do formulário custar oito edições.
 *
 * Preenche EXATAMENTE o que `consultantCprGaps` cobra, e nada além: a lista de
 * pendências do consultor é a especificação deste helper, e o dia em que ela
 * crescer é aqui que a falta aparece.
 */
export async function fillCpr(app: INestApplication, auth: string, code: string) {
  const salvo = await request(app.getHttpServer())
    .put(`/api/v1/barters/${code}/cpr`)
    .set('Authorization', auth)
    .send({
      emitterNationality: 'brasileiro',
      emitterMaritalStatus: 'solteiro',
      emitterProfession: 'produtor rural',
      emitterRg: '10.234.567-8',
      emitterAddress: 'Rua das Acácias',
      emitterAddressNumber: '340',
      emitterCity: 'Maringá/PR',
      deliveryPlace: 'Filial 02 — Granel Santa Tecla',
      cultivar: 'BMX Ativa RR',
      maxMoisture: 14,
      maxImpurities: 1,
      oilContent: 18,
      areas: [
        {
          locality: 'Água Boa',
          city: 'Maringá/PR',
          areaHa: 45.5,
          registryNumber: '12.345',
          registryBook: '2-RG',
          registryDistrict: 'Maringá/PR',
          owners: [{ name: 'Antônio Pereira', document: '111.222.333-44' }],
        },
      ],
    });

  // O SCR é anexo, e não campo: ele sobe por rota própria.
  await request(app.getHttpServer())
    .put(`/api/v1/barters/${code}/cpr/scr`)
    .set('Authorization', auth)
    .attach('file', Buffer.from('%PDF-1.4\nSCR\n%%EOF\n'), {
      filename: 'scr.pdf',
      contentType: 'application/pdf',
    });

  return salvo;
}

/**
 * ENCAMINHA ao gerente, preenchendo a cédula antes.
 *
 * A maioria das suítes só quer a permuta NA MESA DO GERENTE — a cédula é o
 * caminho, não o assunto. Este atalho existe para elas; quem testa o portão em
 * si chama `fillCpr` e `POST /forward` separados, para ver cada metade.
 */
export async function forwardWithCpr(
  app: INestApplication,
  auth: string,
  code: string,
  note = 'Cliente de cinco safras, nunca atrasou entrega.',
) {
  await fillCpr(app, auth, code);
  return request(app.getHttpServer())
    .post(`/api/v1/barters/${code}/forward`)
    .set('Authorization', auth)
    .send({ note });
}
