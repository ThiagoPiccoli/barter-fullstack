import { Injectable, NotFoundException } from '@nestjs/common';
import type { Notice, User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Quantos avisos o painel recebe de uma vez. Aviso é o que a pessoa ainda não
 * viu, e uma pilha maior do que isto já não é lida — é dispensada em bloco.
 */
const NOTICE_LIMIT = 50;

/**
 * OS AVISOS de cada pessoa — o que aconteceu numa permuta que ela acompanha e
 * não pede ação dela. Ver `Notice` no schema.
 *
 * Quem CRIA os avisos não é este serviço: eles nascem dentro do ato que os
 * motiva (ver `noticeToManager` em barters.service.ts), na mesma transação.
 * Aqui só se lê e se dispensa — e só os da própria pessoa.
 */
@Injectable()
export class NoticesService {
  constructor(private readonly prisma: PrismaService) {}

  /** Os ainda não vistos, do mais novo para o mais antigo. */
  unreadFor(user: User): Promise<Notice[]> {
    return this.prisma.notice.findMany({
      where: { userId: user.id, readAt: null },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: NOTICE_LIMIT,
    });
  }

  /**
   * DISPENSA um aviso. Só o próprio: o aviso de outra pessoa responde "não
   * encontrado", como o que não existe — dizer "não é seu" contaria que ele
   * existe, e o que ele diz é sobre uma permuta que quem pergunta talvez nem
   * enxergue.
   *
   * Dispensar de novo não é erro: o aviso já visto continua visto, e a data é a
   * da primeira vez.
   */
  async markRead(user: User, id: number): Promise<Notice> {
    const notice = await this.prisma.notice.findFirst({ where: { id, userId: user.id } });
    if (!notice) throw new NotFoundException('Aviso não encontrado.');
    if (notice.readAt) return notice;
    return this.prisma.notice.update({ where: { id }, data: { readAt: new Date() } });
  }
}
