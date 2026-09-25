import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

/**
 * PrismaClient como provider do Nest. Prisma 7 conecta via driver adapter; a
 * DATABASE_URL é a mesma usada pelo CLI (prisma.config.ts).
 *
 * O banco é PostgreSQL em TODOS os ambientes — dev, teste e produção. Ele é um
 * servidor à parte, e é isso que o sistema precisa dele: várias instâncias da
 * API se coordenam sobre o mesmo dado, e é essa coordenação que sustenta deploy
 * sem downtime, réplica de leitura e backup online.
 *
 * O pool fica com o `pg` (padrão de 10 conexões). Não há nada a ajustar aqui
 * para concorrência: ler e escrever ao mesmo tempo é o comportamento normal do
 * Postgres.
 *
 * O TAMANHO DO POOL é ajustável por DATABASE_POOL_MAX. O padrão de dez serve a
 * um processo só, que é o caso normal; a variável existe para quando houver
 * MAIS DE UM — cada máquina abre o pool dela, e o total é o que o banco vê. Num
 * Postgres gerenciado de plano gratuito, cujo teto de conexões é modesto,
 * quatro máquinas com dez cada já disputam o limite, e o sintoma aparece como
 * `too many connections` sob carga, justamente quando o sistema está em uso.
 *
 * Vale sempre apontar para a URL do POOLER do provedor (no Neon, o host com
 * `-pooler`): é ele que multiplexa de verdade, e o pool daqui passa a ser um
 * teto local em cima de um teto que já existe.
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
