import { Controller, Get, Logger, ServiceUnavailableException } from '@nestjs/common';
import { Public } from './common/decorators';
import { PrismaService } from './prisma/prisma.service';

@Controller()
export class AppController {
  private readonly logger = new Logger('Health');

  constructor(private readonly prisma: PrismaService) {}

  /** Raiz fora do prefixo /api/v1 — só um "sinal de vida" da API. */
  @Public()
  @Get()
  root() {
    return { name: 'Barter API', docs: '/api/v1' };
  }

  /**
   * A pergunta que o balanceador faz antes de mandar tráfego: **esta instância
   * consegue atender?**
   *
   * A raiz acima não responde isso — ela devolve 200 com o processo de pé e o
   * banco inalcançável, que é o pior estado possível para uma verificação de
   * saúde: o balanceador continua entregando requisições para a instância que
   * vai falhar em todas. Por isso aqui há um `SELECT 1`: a única dependência
   * externa que a API tem é o Postgres, e ou ela responde, ou não há o que
   * servir.
   *
   * PÚBLICA de propósito. Sonda não carrega credencial, e o que vaza daqui é
   * "a API está de pé" — que já se descobre pela porta aberta.
   */
  @Public()
  @Get('health')
  async health() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch (error) {
      // O detalhe (host, usuário, motivo da recusa) fica no log; a resposta diz
      // só que não dá para atender agora.
      this.logger.error(
        'Verificação de saúde falhou: o banco não respondeu.',
        error instanceof Error ? error.stack : undefined,
      );
      throw new ServiceUnavailableException('Banco de dados indisponível.');
    }
    return { status: 'ok', database: 'ok' };
  }
}
