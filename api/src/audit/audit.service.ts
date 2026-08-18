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
  /**
   * As UNIDADES, porque designar o gerente de uma é decidir para quem vão as
   * permutas que serão retiradas nela.
   *
   * Sem isto, trocar o responsável por uma unidade tiraria permutas da fila de
   * alguém e as colocaria na de outro sem deixar rastro — e a pergunta que
   * aparece depois ("por que esta permuta parou de aparecer para mim?") não
   * teria como ser respondida. É a mesma natureza do reset de senha: o ato é
   * pequeno, o efeito é sobre quem alcança o quê.
   */
  unitCreated: 'unit.created',
  unitUpdated: 'unit.updated',
  unitDeleted: 'unit.deleted',
  /** O parecer técnico do gerente da unidade — a etapa que antecede a análise. */
  barterOpinion: 'barter.opinion',
  barterReviewed: 'barter.reviewed',
  /**
   * ENTRADA no sistema — e as tentativas que não entraram.
   *
   * A trilha registrava muito bem o que se faz DEPOIS de entrar, e nada sobre
   * o entrar. É a primeira pergunta de qualquer investigação ("quem estava
   * dentro na terça à noite?") e a única evidência de ataque em andamento: dez
   * falhas seguidas na conta do admin não se parecem com nada no registro de
   * atos administrativos, porque nenhum ato aconteceu.
   *
   * O log HTTP mostra `POST /auth/login 400`, mas ele vai para a saída padrão,
   * é volátil e não sabe de QUEM era a conta.
   */
  sessionStarted: 'session.started',
  sessionFailed: 'session.failed',
  sessionLocked: 'session.locked',
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

/**
 * Quem praticou o ato, quando não há um `User` para apontar.
 *
 * Existe por causa da tentativa de login em e-mail que não existe: alguém agiu,
 * e é exatamente esse alguém que interessa registrar, mas não há conta nenhuma
 * a que ele corresponda. Forçar um `User` aqui obrigaria a inventar um.
 */
export interface AuditActor {
  id?: number | null;
  name: string;
  role: string;
}

export interface AuditEntry {
  actor: User | AuditActor;
  action: AuditAction;
  targetType: 'user' | 'unit' | 'barter' | 'season' | 'version' | 'session';
  targetId?: number | null;
  targetLabel: string;
  detail?: string;
}

/** O ator no formato da trilha, venha ele de uma conta ou de um instantâneo. */
function actorSnapshot(actor: User | AuditActor): AuditActor {
  return 'fullName' in actor
    ? { id: actor.id, name: actor.fullName, role: actor.role }
    : { id: actor.id ?? null, name: actor.name, role: actor.role };
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
    const actor = actorSnapshot(entry.actor);
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: actor.id ?? null,
          actorName: actor.name,
          actorRole: actor.role,
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
