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
 *
 * O TAMANHO DO POOL é ajustável por DATABASE_POOL_MAX, e existe por causa de
 * hospedagem sem servidor. Num servidor de verdade há UM processo e UM pool de
 * dez, e a conta fecha. Numa função (ver src/serverless.ts) há uma instância
 * por requisição simultânea, cada uma com o pool dela: trinta chamadas ao mesmo
 * tempo viram trezentas conexões pedidas, e o Postgres gerenciado — cujo plano
 * gratuito costuma parar em algumas dezenas — recusa. O sintoma é
 * `too many connections` sob carga, justamente quando o sistema está sendo
 * usado, e some sozinho quando alguém vai investigar.
 *
 * Em função, portanto: `DATABASE_POOL_MAX=1` e a URL do POOLER do provedor (no
 * Neon, o host com `-pooler`), que é quem multiplexa de verdade. O padrão
 * continua sendo 10 — quem roda o `main.ts` não precisa saber que isto existe.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const configured = Number(process.env.DATABASE_POOL_MAX);
    const max = Number.isInteger(configured) && configured > 0 ? configured : undefined;

    super({
      adapter: new PrismaPg({
        connectionString: process.env.DATABASE_URL ?? 'postgresql://localhost:5432/barter_dev',
        ...(max === undefined ? {} : { max }),
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
