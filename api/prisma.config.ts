import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

/**
 * Configuração do Prisma 7 (a URL saiu do schema.prisma). O runtime usa o
 * driver adapter `@prisma/adapter-pg` (ver src/prisma/prisma.service.ts) com a
 * mesma DATABASE_URL. Os testes e2e apontam para um banco próprio, o
 * `barter_test` do .env.test — a suíte o apaga e re-semeia a cada spec.
 */
export default defineConfig({
  schema: 'prisma/schema.prisma',
  datasource: {
    url: env('DATABASE_URL'),
  },
  migrations: {
    path: 'prisma/migrations',
    seed: 'ts-node prisma/seed.ts',
  },
});
