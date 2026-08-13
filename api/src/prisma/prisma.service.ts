import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaBetterSqlite3 } from '@prisma/adapter-better-sqlite3';
import { PrismaClient } from '@prisma/client';

/**
 * PrismaClient como provider do Nest. Prisma 7 conecta via driver adapter
 * (better-sqlite3); a DATABASE_URL é a mesma usada pelo CLI (prisma.config.ts).
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('Prisma');

  constructor() {
    super({
      adapter: new PrismaBetterSqlite3({
        url: process.env.DATABASE_URL ?? 'file:./prisma/dev.db',
      }),
    });
  }

  async onModuleInit() {
    await this.$connect();
    await this.tuneSqlite();
  }

  /**
   * Ajustes do SQLite que valem para o servidor rodando de verdade.
   *
   * - WAL: leitura e escrita deixam de se bloquear. No modo padrão
   *   (journal_mode=DELETE) uma escrita trava TODAS as leituras enquanto dura,
   *   e o app abre várias listas de uma vez ao entrar.
   * - busy_timeout: em vez de devolver "database is locked" na hora, a
   *   conexão espera até 5s pelo lock. É a diferença entre um erro na cara do
   *   usuário e uma requisição alguns milissegundos mais lenta.
   *
   * WAL fica gravado no arquivo do banco (basta uma vez); o timeout é por
   * conexão. Falhar aqui não impede o servidor de subir — só registra o aviso,
   * porque um banco sem WAL continua funcionando.
   *
   * Efeito colateral a conhecer: o WAL cria os arquivos `dev.db-wal` e
   * `dev.db-shm` ao lado do banco. O `prisma migrate reset` apaga só o
   * `dev.db`, e o WAL órfão sobre um banco novo faz o SQLite responder
   * "database disk image is malformed". Por isso o `predb:reset` no
   * package.json remove os dois antes.
   */
  private async tuneSqlite(): Promise<void> {
    try {
      await this.$queryRawUnsafe('PRAGMA journal_mode = WAL');
      await this.$executeRawUnsafe('PRAGMA busy_timeout = 5000');
    } catch (error) {
      this.logger.warn(
        `Não foi possível aplicar os PRAGMAs de concorrência do SQLite: ${String(error)}`,
      );
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
