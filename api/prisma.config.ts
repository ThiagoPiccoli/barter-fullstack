import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

/**
 * Configuração do Prisma 7 (a URL saiu do schema.prisma). O runtime usa o
 * driver adapter better-sqlite3 (ver src/prisma/prisma.service.ts) com a
 * mesma DATABASE_URL. Testes e2e apontam DATABASE_URL=file:./prisma/test.db.
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
