import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { seedDatabase } from '../prisma/seed-data';
import { AppModule } from '../src/app.module';
import { setupApp } from '../src/app.setup';
import { PrismaService } from '../src/prisma/prisma.service';

/**
 * Sobe a aplicação real (mesmos guards/pipes/interceptor globais do
 * AppModule + setupApp compartilhado com o main.ts). O banco é o SQLite de
 * teste apontado pela DATABASE_URL do script test:e2e.
 */
export async function createTestApp(): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  // `bodyParser: false` espelha o main.ts: quem registra o parser (com limite
  // explícito) é o setupApp, e o servidor de teste precisa do mesmo.
  const app = moduleRef.createNestApplication({ logger: false, bodyParser: false });
  setupApp(app);
  await app.init();
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

/** Loga (senha padrão do seed: 123456) e devolve o token Bearer. */
export async function loginAs(app: INestApplication, email: string): Promise<string> {
  const response = await request(app.getHttpServer())
    .post('/api/v1/auth/login')
    .send({ email, password: '123456' });
  return response.body.data.token as string;
}

export const ADMIN = 'admin@agrobarter.com.br';
export const JOAO = 'joao.silva@agrobarter.com.br';
export const ANA = 'ana.ferreira@agrobarter.com.br';

/* Retaguarda (um por papel novo). */
export const GERENTE = 'gerente@agrobarter.com.br';
export const COMITE = 'comite@agrobarter.com.br';
export const FATURISTA = 'faturista@agrobarter.com.br';

/** Os três papéis de retaguarda criados junto com o RBAC, para varrer todos. */
export const BACK_OFFICE = [GERENTE, COMITE, FATURISTA];
