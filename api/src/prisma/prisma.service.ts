import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

/**
 * PrismaClient como provider do Nest. Prisma 7 conecta via driver adapter; a
 * DATABASE_URL é a mesma usada pelo CLI (prisma.config.ts).
 *
 * O banco é PostgreSQL. Antes era SQLite embutido no processo, e a troca
 * aconteceu ANTES da primeira carga real de propósito: sem dado de produção, o
 * custo foi reescrever migrations; com dado, seria janela de parada e script de
 * transferência. O que o SQLite não dava não era desempenho — era operação:
 * uma segunda instância da API sobre o mesmo arquivo não se coordena, então não
 * havia deploy sem downtime, réplica de leitura nem backup online.
 *
 * O pool fica com o `pg` (padrão de 10 conexões). Não há PRAGMA a ajustar aqui:
 * concorrência de leitura e escrita é o comportamento normal do Postgres, e era
 * justamente o que os PRAGMAs do SQLite tentavam emular.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    super({
      adapter: new PrismaPg({
        connectionString: process.env.DATABASE_URL ?? 'postgresql://localhost:5432/barter_dev',
      }),
    });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
