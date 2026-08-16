import { Injectable, Logger, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { tokenIdleDays } from './token.util';

/** De quanto em quanto tempo a varredura roda. */
const SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;

/**
 * A FAXINA das sessões mortas.
 *
 * O AuthGuard já apaga o token vencido quando alguém tenta usá-lo, e isso
 * basta para a SEGURANÇA: sessão vencida não abre porta nenhuma. O que ele não
 * resolve é a sobra — a sessão que ninguém tenta usar de novo nunca é visitada,
 * então a linha fica no banco para sempre. É o caso mais comum de todos:
 * aparelho trocado, app desinstalado, consultor que saiu da cooperativa.
 *
 * Sem isto a tabela só cresce, e cresce com dados de autenticação: um backup
 * vazado de dois anos atrás traz junto todas as sessões que já existiram.
 * Guardar o que não serve mais é aumentar o estrago do dia ruim.
 *
 * Um `setInterval` — e não um agendador de verdade — porque é o que o problema
 * pede: uma varredura por processo, sem coordenação e sem calendário. Com mais
 * de uma instância da API, todas varrem, e o `deleteMany` é idempotente: a
 * segunda não encontra nada.
 */
@Injectable()
export class SessionCleanupService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('Sessions');
  private timer?: NodeJS.Timeout;

  constructor(private readonly prisma: PrismaService) {}

  onModuleInit(): void {
    // `unref` para o temporizador não segurar o processo de pé: sem ele, a
    // suíte de testes e qualquer `Ctrl+C` esperariam seis horas pelo próximo
    // ciclo.
    this.timer = setInterval(() => void this.sweep(), SWEEP_INTERVAL_MS);
    this.timer.unref();
    void this.sweep();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  /**
   * Apaga o que já não vale: vencido pelo prazo absoluto ou parado tempo
   * demais. Os dois critérios são os mesmos do AuthGuard — se divergissem,
   * existiria sessão que a faxina apaga e o guard aceitaria, ou o contrário.
   */
  async sweep(): Promise<number> {
    const now = new Date();
    const idleSince = new Date(now.getTime() - tokenIdleDays() * 24 * 60 * 60 * 1000);

    try {
      const { count } = await this.prisma.accessToken.deleteMany({
        where: { OR: [{ expiresAt: { lte: now } }, { lastUsedAt: { lte: idleSince } }] },
      });
      if (count > 0) this.logger.log(`${count} sessão(ões) expirada(s) removida(s).`);
      return count;
    } catch (error) {
      // Banco fora do ar não pode derrubar o servidor por causa da faxina: ela
      // roda de novo em seis horas, e nada depende de ela ter rodado.
      this.logger.error(
        'Falha ao remover sessões expiradas.',
        error instanceof Error ? error.stack : undefined,
      );
      return 0;
    }
  }
}
