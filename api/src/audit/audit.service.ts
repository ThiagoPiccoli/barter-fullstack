import { Injectable, Logger } from '@nestjs/common';
import type { AuditLog, User } from '@prisma/client';
import { Paginated, windowOf } from '../common/pagination';
import { PrismaService } from '../prisma/prisma.service';
import type { ListAuditLogsQuery } from './dto/audit.dto';

/**
 * Os atos que deixam rastro. Lista fechada: auditar "tudo" produz ruído que
 * ninguém lê, e o que interessa aqui é o que muda QUEM tem acesso e o que
 * decide dinheiro.
 */
export const AUDIT_ACTION = {
  userCreated: 'user.created',
  userUpdated: 'user.updated',
  userPasswordReset: 'user.password-reset',
  userDeleted: 'user.deleted',
  barterReviewed: 'barter.reviewed',
  // O lançamento do Barter decide POR QUANTO a cooperativa troca insumo por
  // grão: publicar uma versão, corrigir um preço dentro dela e encerrá-la
  // valem tanto quanto aprovar uma permuta, e pelo mesmo motivo — é dinheiro.
  seasonOpened: 'season.opened',
  seasonClosed: 'season.closed',
  versionPublished: 'barter.version-published',
  versionPriceChanged: 'barter.price-changed',
  versionClosed: 'barter.version-closed',
} as const;

export type AuditAction = (typeof AUDIT_ACTION)[keyof typeof AUDIT_ACTION];

export interface AuditEntry {
  actor: User;
  action: AuditAction;
  targetType: 'user' | 'barter' | 'season' | 'version';
  targetId?: number | null;
  targetLabel: string;
  detail?: string;
}

@Injectable()
export class AuditService {
  private readonly logger = new Logger('Audit');

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Grava a linha da trilha.
   *
   * NÃO derruba a operação se a gravação falhar. É uma escolha, e vale
   * explicá-la: o ato auditado (redefinir a senha de alguém que perdeu o
   * acesso) já aconteceu e é o que a pessoa precisa; abortar a resposta por
   * causa do registro transformaria uma falha de auditoria em indisponibilidade
   * do sistema. A perda vira ERRO no log, que é onde o alarme deve tocar.
   *
   * A troca seria outra num sistema em que a trilha tem valor legal — aí ela
   * entra na MESMA transação do ato, e sem trilha não há ato. Se o faturamento
   * exigir isso, é aqui que muda.
   */
  async record(entry: AuditEntry): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: entry.actor.id,
          actorName: entry.actor.fullName,
          actorRole: entry.actor.role,
          action: entry.action,
          targetType: entry.targetType,
          targetId: entry.targetId ?? null,
          targetLabel: entry.targetLabel,
          detail: entry.detail ?? null,
        },
      });
    } catch (error) {
      this.logger.error(
        `Falha ao registrar auditoria (${entry.action} sobre ${entry.targetLabel})`,
        error instanceof Error ? error.stack : undefined,
      );
    }
  }

  /** Mais recentes primeiro — é assim que se investiga: do agora para trás. */
  async list(query: ListAuditLogsQuery): Promise<Paginated<AuditLog>> {
    const { take, skip } = windowOf(query);
    const where = {
      ...(query.action ? { action: query.action } : {}),
      ...(query.targetType ? { targetType: query.targetType } : {}),
    };

    const [items, total] = await this.prisma.$transaction([
      this.prisma.auditLog.findMany({
        where,
        orderBy: [{ at: 'desc' }, { id: 'desc' }],
        take,
        skip,
      }),
      this.prisma.auditLog.count({ where }),
    ]);

    return new Paginated(items, total, take, skip);
  }
}
